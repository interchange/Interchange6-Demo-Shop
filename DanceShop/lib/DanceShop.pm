use utf8;

package DanceShop;

=encoding utf8

=head1 NAME

DanceShop - base Demo Shop for Interchange 6

=head1 VERSION

0.001

=head1 CHECKOUT

The DanceShop has two checkout types: single and multi.
Currently the default configuration enables the multistep
checkout.

=cut

our $VERSION = '0.001';

use Dancer ':syntax';
use Dancer::Plugin;
use Dancer::Plugin::Ajax;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Interchange6;
use Dancer::Plugin::Interchange6::Routes;
use Dancer::Plugin::PageHistory;
use DanceShop::Routes;
use DanceShop::Paging;
use DanceShop::SearchResults;
use DateTime;
use List::Util qw(first);
use POSIX qw/ceil/;
use Scalar::Util 'blessed';
use Try::Tiny;
use URL::Encode qw/url_decode_utf8/;

set session => 'DBIC';
set session_options => { schema => schema };

=head1 HOOKS

The DanceShop makes use of the following hooks.

=head2 before_layout_render

Add cart token.

Create tokens for all L<Interchange6::Schema::Result::Navigation> menus where
C<type> is C<nav> with the token name being the C<scope> prepended with C<nav->.

=cut

hook 'before_layout_render' => sub {
    my $tokens = shift;

    $tokens->{cart} = cart;

    # build menu tokens

    my @nav = shop_navigation->search(
        {
            'me.active'    => 1,
            'me.type'      => 'nav',
            'me.parent_id' => undef,
        },
        {
            prefetch => 'active_children',
            order_by => [
                { -desc => 'me.priority' },
                'me.name',
                { -desc => 'active_children.priority' },
                'active_children.name',
            ],
        }
    )->hri->all;

    foreach my $record (@nav) {
        push @{ $tokens->{ 'nav-' . $record->{scope} } }, $record;
    }

    # find 2 products with the largest percentage discount for each top-level
    # nav to add to megadrop
    foreach my $nav ( @{ $tokens->{"nav-menu-main"} } ) {

        $nav->{products} = DanceShop::offers(
            2,
            {
                -or => [
                    {
                        'navigation_products.navigation_id' =>
                          $nav->{navigation_id}
                    },
                    {
                        'navigation_products_2.navigation_id' =>
                          $nav->{navigation_id}
                    }
                ]
            },
            {
                join => [
                    'navigation_products',
                    { 'canonical' => 'navigation_products' },
                ]
            }
        );
    }

};

=head2 before_navigation_search

This hooks replaces the standard L<Dancer::Plugin::Interchange6::Routes>
navigation route to enable us to alter product listing items per page on 
the fly and sort order.

=cut

hook 'before_navigation_search' => sub {
    my $tokens = shift;

    return if $tokens->{template} ne 'product-listing';

    add_to_history( type => 'navigation', name => $tokens->{navigation}->name );

    my $products =
      $tokens->{navigation}->navigation_products->search_related('product')
      ->active;

    my %query = params('query');

    my $routes_config = config->{plugins}->{'Interchange6::Routes'} || {};

    my $schema = shop_schema;

    # find facets in query params

    my %query_facets = map {
        $_ =~ s/^f\.//
          && url_decode_utf8($_) =>
          [ split( /\!/, url_decode_utf8( $query{"f.$_"} ) ) ]
    } grep { /^f\./ } keys %query;

    # setup search results handler

    my $results_handler = DanceShop::SearchResults->new(
        routes_config => $routes_config,
        tokens        => $tokens,
        query         => \%query,
    );

    # now we know the view we can correct the template token

    $tokens->{template} = "product-listing-" . $results_handler->view;

    # Filter products based on facets in query params if there are any.
    # This loopy query stuff is terrible - should be a much better way
    # to do this but I haven't found one yet that is as fast.

    if ( keys %query_facets ) {

        my @skus = $products->get_column( $products->me('sku') )->all;

        foreach my $key ( keys %query_facets ) {

            @skus = $schema->resultset('Product')->search(
                {
                    -and => [
                        'product.sku' => { -in => \@skus },
                        -or           => [
                            -and => [
                                'attribute.name' => $key,
                                'attribute_value.value' =>
                                  { -in => $query_facets{$key} }
                            ],
                            -and => [
                                'attribute_2.name' => $key,
                                'attribute_value_2.value' =>
                                  { -in => $query_facets{$key} }
                            ]
                        ]
                    ]
                },
                {
                    alias   => 'product',
                    columns => ['product.sku'],
                    join    => [
                        {
                            product_attributes => [
                                'attribute',
                                {
                                    product_attribute_values =>
                                      'attribute_value'
                                }
                            ]
                        },
                        {
                            variants => {
                                product_attributes => [
                                    'attribute',
                                    {
                                        product_attribute_values =>
                                          'attribute_value'
                                    }
                                ]
                            }
                        }
                    ],
                },
            )->get_column('product.sku')->all;
        }

        $products = $schema->resultset('Product')->search(
            {
                'product.sku' => { -in => \@skus }
            },
            {
                alias => 'product',
            }
        );
    }

    # facets

    # TODO: counting facets needs review since this can be slow

    # start by grabbing the non-variant then variant facets into @facet_list
    my $cond = { 'attribute.name' => { '!=' => undef } };

    $cond = {
        -or => [
            'attribute.name' => { -not_in => [ keys %query_facets ] },
            map {
                -and => [
                    { 'attribute.name' => $_ },
                    {
                        'attribute_value.value' => { -in => $query_facets{$_} }
                    }
                  ]
            } keys %query_facets
        ]
    } if keys %query_facets;

    my $attrs = {
        join => {
            product_attributes => [
                'attribute', { product_attribute_values => 'attribute_value' }
            ]
        },
        columns    => [],
        '+columns' => [
            { name  => 'attribute.name' },
            { value => 'attribute_value.value' },
            { title => 'attribute_value.title' },
            { count => { count => { distinct => 'product.sku' } } },
        ],
        order_by => [
            { -desc => 'attribute_value.priority' },
            { -asc  => 'attribute_value.title' },
        ],
        group_by => [
            "attribute.name",        "attribute_value.value",
            "attribute_value.title", "attribute_value.priority",
        ],
    };
    my @facet_list = $products->search( $cond, $attrs )->hri->all;

    # this is the expensive one...
    $attrs->{join} = {
        variants => {
            product_attributes => [
                'attribute', { product_attribute_values => 'attribute_value' }
            ]
        }
    };
    push @facet_list, $products->search( $cond, $attrs )->hri->all;

    # now we need the facet groups (name, title & priority)
    # this can also be rather expensive
    my $facet_group_rset1 = $products->search(
        { 'attribute.name' => { '!=' => undef } },
        {
            join       => { product_attributes => 'attribute' },
            columns    => [],
            '+columns' => {
                name     => 'attribute.name',
                title    => 'attribute.title',
                priority => 'attribute.priority',
            },
            distinct => 1,
        }
    );
    my $facet_group_rset2 = $products->search(
        { 'attribute.name' => { '!=' => undef } },
        {
            join       => { variants => { product_attributes => 'attribute' } },
            columns    => [],
            '+columns' => {
                name     => 'attribute.name',
                title    => 'attribute.title',
                priority => 'attribute.priority',
            },
            distinct => 1,
        }
    );

    my $facet_group_rset =
      $facet_group_rset1->union($facet_group_rset2)
      ->distinct( $products->me('name') )->order_by(
        [
            { -desc => $products->me('priority') },
            { -asc  => $products->me('title') }
        ]
      );

    # now construct facets token
    my @facets;
    my %seen;
    while ( my $facet_group = $facet_group_rset->next ) {

        # it could in theory be possible to have two attributes with the same
        # name in the facet groups list so we skip if we've seen it before
        unless ( $seen{ $facet_group->name } ) {

            my $data;
            my @results = grep { $_->{name} eq $facet_group->name } @facet_list;
            $data->{title} = $facet_group->get_column('title');

            $data->{values} = [
                map {
                    {
                        name  => $facet_group->name,
                        value => $_->{value},
                        title => $_->{title},
                        count => $_->{count},
                        unchecked => 1,    # cheaper to use param than container
                    }
                } @results
            ];

            if ( defined $query_facets{ $facet_group->name } ) {
                foreach my $value ( @{ $data->{values} } ) {
                    if ( grep { $_ eq $value->{value} }
                        @{ $query_facets{ $facet_group->name } } )
                    {
                        $value->{checked} = "yes";
                        delete $value->{unchecked};
                    }
                }
            }
            push @facets, $data;
        }
    }
    $tokens->{facets} = \@facets;

    # apply product resultset methods then sort and page

    my $order     = $results_handler->order_by;
    my $direction = $results_handler->order_direction;

    # we need to prepend alias to most columns but not all
    unless ( $order =~ /^(average_rating|selling_price)$/ ) {
        $order = $products->me($order);
    }

    # restrict returned columns in products query and add required
    # resultset methods

    $products = $products->columns(
        [ 'sku', 'name', 'uri', 'price', 'short_description' ] )
      ->with_average_rating->with_lowest_selling_price(
        { users_id => session('logged_in_user_id') } )
      ->with_quantity_in_stock->with_variant_count->order_by(
        { "-$direction" => [$order] } );

    # pager

    my $pager;
    if ( $tokens->{per_page} ) {

        $products =
          $products->limited_page( $tokens->{page}, $tokens->{per_page} );

        $pager = $products->pager;

        if ( $tokens->{page} > $pager->last_page ) {

            # we're past the last page which happens a lot if we start on a high
            # page then results are restricted via facets so reset the pager

            $tokens->{page} = $pager->last_page;
            $products =
              $products->limited_page( $tokens->{page}, $tokens->{per_page} );
            $pager = $products->pager;
        }
        $tokens->{pager} = $pager;
    }

    # grid view can look messy unless we deliver products in nice rows of
    # three products per row

    if ( $results_handler->view eq 'grid' ) {
        my @grid;
        my @products = $products->all;
        while ( my @row = splice( @products, 0, 3 ) ) {
            push @grid, +{ row => \@row };
        }
        $tokens->{products} = \@grid;
    }
    else {
        $tokens->{products} = $products;
    }

    # pagination

    if ( $pager && $pager->last_page > 1 ) {

        # we want pagination as there is more than one page of products

        my $first_page = 1;
        my $last_page  = $pager->last_page;

        if ( $pager->last_page > 5 ) {

            # more than 5 pages so we might need to start later than page 1

            if ( $pager->current_page <= 3 ) {
                $last_page = 5;
            }
            elsif ( $pager->last_page - $pager->current_page < 3 ) {
                $first_page = $pager->last_page - 4;
            }
            else {
                $first_page = $pager->current_page - 2;
                $last_page  = $pager->current_page + 2;
            }

            my @pages = map {
                +{
                    page => $_,
                    uri  => $_ == $pager->current_page
                    ? undef
                    : uri_for( $tokens->{navigation}->uri . '/' . $_, \%query ),
                    active => $_ == $pager->current_page ? " active" : undef,
                  }
            } $first_page .. $last_page;

            $tokens->{pagination} = \@pages;

            if ( $pager->current_page > 1 ) {

                # previous page

                my $previous = $pager->current_page > 3 ? $first_page - 1 : 1;

                $tokens->{pagination_previous} =
                  uri_for( $tokens->{navigation}->uri . '/' . $previous,
                    \%query );
            }

            if ( $pager->current_page < $pager->last_page ) {

                # next page

                my $next =
                    $pager->last_page - $pager->current_page > 3
                  ? $last_page + 1
                  : $pager->last_page;

                $tokens->{pagination_next} =
                  uri_for( $tokens->{navigation}->uri . '/' . $next, \%query );
            }
        }
    }

    # breadcrumb and page name

    $tokens->{breadcrumb} = [ $tokens->{navigation}->ancestors ];
    $tokens->{"page-name"} = $tokens->{navigation}->name;

    # navigation siblings

    my $siblings_with_self = $tokens->{navigation}->siblings_with_self;

    my $siblings = [
        $siblings_with_self->columns( [qw/navigation_id uri name/] )
          ->add_columns(
            {
                count => $siblings_with_self->correlate('navigation_products')
                  ->search_related('product')->active->count_rs->as_query
            }
          )->order_by('!priority,name')->hri->all
    ];

    foreach my $sibling (@$siblings) {
        $sibling->{selected} = 1
          if $sibling->{navigation_id} == $tokens->{navigation}->navigation_id;
    }
    $tokens->{"nav-siblings"} = $siblings;

    # add extra js

    $tokens->{"extra-js-file"} = 'product-listing.js';

    # call the template and throw it so that the hook does not return
    # and request processing finishes

    Dancer::Continuation::Route::Templated->new(
        return_value => template( $tokens->{template}, $tokens ) )->throw;
};

hook 'before_product_display' => sub {
    my $tokens = shift;

    my $product = $tokens->{product};

    # Add recently viewed products token before we add this page to history
    add_recent_products( $tokens, 4 );

    # an interesting page
    add_to_history(
        type       => 'product',
        name       => $product->name,
        attributes => { sku => $product->sku }
    );

    # Similar products
    # we have 2 panels of 2 items so get 4 then split into 2 iterators
    add_similar_products( $tokens, 4, $product->sku );
    $tokens->{similar1} = [ splice @{ $tokens->{similar_products} }, 0, 2 ];
    $tokens->{similar2} = [ splice @{ $tokens->{similar_products} }, 0, 2 ];
    delete $tokens->{similar_products};

    # TODO: setting of selling_price and discount should not be in demo shop
    my $roles;
    if (logged_in_user) {
        $roles = user_roles;
    }
    $tokens->{selling_price} = $product->selling_price( { roles => $roles } );

    $tokens->{discount} = $product->discount_percent;

    my $in_stock = $product->quantity_in_stock;
    if ( defined $in_stock ) {
        if ( $in_stock == 0 ) {

            # TODO: we need something in the schema (product attributes?)
            # to set this token
            # TODO: should say something along the lines of "try another
            # variant" if product has variants
            $tokens->{"product-availability"} = "Currently out of stock";
        }
        elsif ( $in_stock <= 10 ) {

            # TODO: maybe this ^^ number can be configured somewhere?
            $tokens->{"low-stock-alert"} = $in_stock;
        }
    }

    my @reviews;
    my $reviews = $product->top_reviews;
    while ( my $review = $reviews->next ) {
        push @reviews,
          {
            rating  => $review->rating * 1,     # convert from string
            author  => $review->author->name,
            created => $review->created,
            content => $review->content,
          };

    }
    $tokens->{reviews}         = \@reviews;
    $tokens->{reviews_count}   = scalar @reviews;
    $tokens->{"extra-js-file"} = 'product-page.js';
    $tokens->{breadcrumb}      = $product->path;
    $tokens->{"page-name"}     = $product->name;
};

=head1 SUBROUTINES

=head2 add_recent_products($tokens, $quantity)

Add recent_products token containing the most recently-viewed products.

This sub must be given the current template tokens hash reference and
quantity of results wanted.

=cut

sub add_recent_products {
    my ( $tokens, $quantity ) = @_;

    return if ( !defined $tokens || !defined $quantity );

    # we want the 4 most recent unique products viewed

    my %seen;
    my @skus;
    foreach my $product ( @{ history->product } ) {

        # not current product
        next if $product->path eq request->path;

        if ( my $sku = $product->attributes->{sku} ) {
            if ( !$seen{$sku} ) {
                $seen{$sku} = 1;
                push @skus, $sku;
            }
        }
        last if scalar( @skus == 4 );
    }

    my $products = schema->resultset('Product')->search(
        {
            'product.sku' => {
                -in => \@skus
            }
        },
        {
            alias => 'product',
        }
    );

    if ( $products->has_rows ) {

        # we have some results so set the token

        $tokens->{recent_products} =
          [ $products->listing( { users_id => session('logged_in_user_id') } )
              ->all ];
    }
}

=head add_similar_products( $tokens, $quantity, $sku );

Add similar_products token containing the most recently-viewed products.
Returned products will be active and canonical.

This sub must be given the current template tokens hash reference,
the quantity of results wanted and a product sku.

NOTE: should use solr to gather some SKUs since the subquery used here sucks
way too much.

=cut

sub add_similar_products {
    my ( $tokens, $quantity, $sku ) = @_;

    return if ( !defined $tokens || !defined $quantity );

    my $schema = schema;

    $tokens->{similar_products} = [
        $schema->resultset('Product')->search(
            {
                'product.active'                    => 1,
                'product.canonical_sku'             => undef,
                'product.sku'                       => { '!=', $sku },
                'navigation_products.navigation_id' => {
                    '=' => $schema->resultset('NavigationProduct')->search(
                        {
                            'me.sku' => $sku,
                        },
                        {
                            order_by => { -desc => 'me.priority' },
                            rows     => 1,
                        }
                    )->get_column('navigation_id')->as_query
                }
            },
            {
                alias => 'product',
                join  => 'navigation_products',
                rows  => $quantity,
            }
        )->listing->hri->all
    ];
}

=head2 offers( $number_wanted, $cond, $attrs );

=cut

sub offers {
    my $wanted = shift;
    die "offers needs valid wanted" unless ( $wanted && $wanted =~ /^\d+$/ );

    my %cond  = %{ shift || {} };
    my %attrs = %{ shift || {} };

    my @join = ( 'price_modifiers' );
    if ( $attrs{join} ) {
        if ( ref($attrs{join}) eq 'ARRAY' ) {
            push @join , @{ $attrs{join} };
        }
        else {
            push @join , $attrs{join};
        }
        delete $attrs{join};
    }

    # we need our best two offers

    my $today = shop_schema->format_datetime(DateTime->today);
    my $products = shop_product->search(
        {
            'me.active'                  => 1,
            'price_modifiers.start_date' => [ undef, { '<=', $today } ],
            'price_modifiers.end_date'   => [ undef, { '>=', $today } ],
            'price_modifiers.quantity' => { '<=' => 1 },
            'price_modifiers.price' => { '!=', undef },
            %cond,
        },
        {
            columns => [ 'sku', 'name', 'uri', 'price' ],
            join      => \@join,
            '+select' => {
                max => \q[ (me.price - price_modifiers.price)/me.price ],
                -as => 'discount_percent'
            },
            order_by => { -desc => 'discount_percent' },
            distinct => 1,
            rows     => 1,
            %attrs,
        }
    )->with_quantity_in_stock;

    # possible role-based pricing
    my $user  = logged_in_user;
    if ($user) {
        $products = $products->search(
            {
                'price_modifiers.roles_id' =>
                  [ undef, $user->roles->get_column('roles_id')->all ]
            }
        );
    }
    else {
        $products =
          $products->search( { 'price_modifiers.roles_id' => undef } );
    }

    my @offers;
    my @skus;
    while ( scalar @offers < $wanted ) {

        my $offer;
        if ( scalar @skus ) {
            $offer = $products->search(
                {
                    'me.sku' => { -not_in => \@skus }
                }
            )->next;
        }
        else {
            $offer = $products->next;
        }

        last unless $offer;

        push @offers, $offer;
        push @skus, $offer->canonical_sku || $offer->sku;
    }

    my $num_offers = scalar @offers;

    if ( $num_offers < $wanted ) {

        print STDERR to_dumper( \%cond );
        print STDERR to_dumper( \%attrs );

        # not enough offers so add some more canonical products to fill
        # in the gaps

        my @skus = map { $_->canonical_sku || $_->sku } @offers;

        push @offers,
          shop_product->search(
            {
                'me.active'        => 1,
                'me.sku'           => { -not_in => \@skus },
                'me.canonical_sku' => undef,
                %cond,
            },
            {
                join => \@join,
                %attrs
            }
          )->rand( $wanted - $num_offers )->with_quantity_in_stock->all;
    }

    return \@offers;
};

shop_setup_routes;

true;
