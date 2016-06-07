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

=head1 TEST DATA

After you set your configuration with the proper information
for your database, the following script will populate it
with initial test data:

    ./bin/populate

=cut

our $VERSION = '0.001';

use Dancer2;
use Dancer2::Plugin::Ajax;
use Dancer2::Plugin::Auth::Extensible;
use Dancer2::Plugin::Cache::CHI;
use Dancer2::Plugin::DBIC;
use Dancer2::Plugin::Interchange6;
use Dancer2::Plugin::Interchange6::Routes;
use Dancer2::Plugin::PageHistory;
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

    my $menu_main = cache_get 'nav-menu-main';

    # try to get nav from memory cache
    my $nav = cache(
        memory => { driver => 'RawMemory', global => 1, expires_in => 300 } )
      ->get('nav');

    if ( !$nav ) {

        my @navs = shop_navigation->search(
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

        # stash navs where scope is not menu-main

        push( @{ $nav->{ 'nav-' . $_->{scope} } }, $_ )
          for grep { $_->{scope} ne 'menu-main' } @navs;

        # now handle menu-main

        my @menu_main = grep { $_->{scope} eq 'menu-main' } @navs;

        # find 2 products with the largest percentage discount for megadrop

        foreach my $nav (@menu_main) {

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

        # construct nav-main-menu template

        $nav->{'nav-menu-main'} = template 'fragments/nav-menu-main',
          { "nav-menu-main" => \@menu_main }, { layout => undef };

        # cache all our navs

        cache('memory')->set( nav => $nav );
    }

    # put $nav into tokens
    while ( my ( $key, $value ) = each %$nav ) {
        $tokens->{$key} = $value;
    }

    $tokens->{icecat} = 1
      if shop_schema->resultset('Setting')
      ->single( { scope => 'global', name => 'icecat', value => 'true' } );
};

=head2 before_navigation_search

This hooks replaces the standard L<Dancer2::Plugin::Interchange6::Routes>
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

    # get ordered product listing

    $products = $products->listing->order_by( { "-$direction" => [$order] } );

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

    # prefetch media

    $products = $products->with_media;

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
        $tokens->{products} = [ $products->all ];
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

    my $siblings_with_self = $tokens->{navigation}->siblings_with_self->search(
        {
            scope => $tokens->{navigation}->scope,
            type  => $tokens->{navigation}->type
        }
    );

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

    Dancer2::Continuation::Route::Templated->new(
        return_value => template( $tokens->{template}, $tokens ) )->throw;
};

hook 'before_product_display' => sub {
    my $tokens = shift;

    my $product = $tokens->{product};

    my $images = $product->media_by_type('image');
    $tokens->{image} = $images->first->uri;

    if ( $images->count > 1 ) {
        $tokens->{thumbs} = [ $images->hri->all ];
    }

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
    my @similar = @{ delete $tokens->{similar_products} };
    $tokens->{similar1} = [ splice @similar, 0, 2 ] if @similar;
    $tokens->{similar2} = [ splice @similar, 0, 2 ] if @similar;

    $tokens->{selling_price} = $product->selling_price;

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
        push @reviews, {
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
            prefetch => { media_products => 'media' },
        }
    )->with_lowest_selling_price->with_quantity_in_stock;

    if ( $products->has_rows ) {

        # we have some results so set the token

        $tokens->{recent_products} =
          [ $products->listing( { users_id => session('logged_in_user_id') } )
              ->all ];
    }
}

=head2 add_similar_products( $tokens, $quantity, $sku );

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
                prefetch => { media_products => 'media' },
            }
        )->listing->all
    ];
}

=head2 offers( $number_wanted, $cond, $attrs );

=cut

sub offers {
    my ( $wanted, $cond, $attrs ) = @_;
    die "offers needs valid wanted" unless ( $wanted && $wanted =~ /^\d+$/ );

    # we need our best $wanted offers

    my $today    = shop_schema->format_datetime( DateTime->today );
    my $subquery = shop_product->search(
        {
            'me.active'                  => 1,
            'price_modifiers.start_date' => [ undef, { '<=', $today } ],
            'price_modifiers.end_date'   => [ undef, { '>=', $today } ],
            'price_modifiers.quantity'   => [ undef, { '<=', 1 } ],
        },
        {
            columns   => ['sku'],
            join      => 'price_modifiers',
            '+select' => {
                max => \q[
                    CASE
                        WHEN price_modifiers.price_modifiers_id IS NOT NULL
                            THEN (me.price - price_modifiers.price)/me.price
                        ELSE 0
                    END
                    ],
                -as => 'discount_percent'
            },
            order_by => { -desc => 'discount_percent' },
            group_by => 'me.sku',
            rows     => $wanted,
        }
        )->search( $cond, $attrs )->get_column('sku')->as_query;

    return [
        shop_product->search(
            {
                'me.sku'       => { -in => $subquery },
                'media.active' => 1,
                'media.label'     => [ '', 'low', 'thumb' ],
                'media_type.type' => 'image',
            },
            {
                join => [ { media_products => { media => 'media_type' } } ],
                prefetch => { media_products => 'media' },
                order_by => 'media.priority',
            }
        )->all
    ];
}
shop_setup_routes;

true;
