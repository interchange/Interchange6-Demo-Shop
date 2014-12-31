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
use DanceShop::Routes::Checkout;
use DateTime;
use POSIX qw/ceil/;
use Try::Tiny;
use URL::Encode qw/url_decode_utf8/;

set session => 'DBIC';
set session_options => {schema => schema};

=head1 HOOKS

The DanceShop makes use of the following hooks.

=head2 before_layout_render

Create tokens for all L<Interchange6::Schema::Result::Navigation> menus where
C<type> is C<nav> with the token name being the C<scope> prepended with C<nav->.

=cut

hook 'before_layout_render' => sub {
    my $tokens = shift;

    $tokens->{cart} = cart;

    my $nav = shop_navigation->search(
        {
            type => 'nav',
            parent_id => undef,
        },
        {
            order_by => { -desc => 'priority'},
        }
    );
    while (my $record = $nav->next) {
        push @{$tokens->{'nav-' . $record->scope}}, $record;
    };
};

=head2 before_navigation_search

This hooks replaces the standard L<Dancer::Plugin::Interchange6::Routes>
navigation route to enable us to alter product listing items per page on 
the fly and sort order.

=cut

hook 'before_navigation_search' => sub {
    my $tokens = shift;

    return if $tokens->{template} ne 'product-listing';

    my %query = params('query');

    my $routes_config = config->{plugin}->{'Interchange6::Routes'};

    my $schema = shop_schema;

    # find facets in query params

    my %query_facets = map {
        $_ =~ s/^f\.//
          && url_decode_utf8($_) =>
              [ split( /\!/, url_decode_utf8( $query{"f.$_"} ) ) ]
    } grep { /^f\./ } keys %query;

    # determine which view to display

    my $view = $query{view};
    if (   !defined $view
        || !grep { $_ eq $view } (qw/grid list simple compact/) )
    {
        $view = $routes_config->{navigation}->{default_view} || 'list';
    }
    $tokens->{"navigation-view-$view"} = 1;

    # rows (products per page) 

    my $rows = $query{rows};
    if ( !defined $rows || $rows !~ /^\d+$/ ) {
        $rows = $routes_config->{navigation}->{records} || 10;
    }

    my @rows_iterator;
    if ( $view eq 'grid' ) {
        $rows = ceil($rows/3)*3;
        $tokens->{per_page_iterator} = [ map { +{ value => 12 * $_ } } 1 .. 4 ];
    }
    else {
        $tokens->{per_page_iterator} = [ map { +{ value => 10 * $_ } } 1 .. 4 ];
    }
    $tokens->{per_page} = $rows;

    # order

    my @order_by_iterator = (
        { value => 'priority',      label => 'Position' },
        { value => 'selling_price', label => 'Price' },
        { value => 'name',          label => 'Name' },
        { value => 'sku',           label => 'SKU' },
    );
    my $order     = $query{order};
    my $direction = $query{dir};
    if (   !defined $order
        || !grep { $_ eq $order } map { $_->{value} } @order_by_iterator )
    {
        $order     = 'priority';
        $direction = 'desc';
    }
    my @order_by = ( "product.$order" );
    unshift( @order_by, "product.priority" ) if ( $order eq 'priority' ); 

    my @group_by = (
        'product.sku',               'product.name',
        'product.uri',               'product.price',
        'product.short_description', 'inventory.quantity'
    );
    if ( $order eq "selling_price") {
        @order_by = ( "selling_price" );
    }

    if ( !defined $direction || $direction !~ /^(asc|desc)/ ) {
        $direction = 'asc';
    }

    $tokens->{order_by_iterator} = \@order_by_iterator;
    $tokens->{order_by} = $order;
    if ( $direction eq 'asc' ) {
        $tokens->{reverse_order} = 'desc';
        $tokens->{order_by_glyph} =
          q(<span class="glyphicon glyphicon-arrow-up"></span>);
    }
    else {
        $tokens->{reverse_order} = 'asc';
        $tokens->{order_by_glyph} =
          q(<span class="glyphicon glyphicon-arrow-down"></span>);
    }

    # products

    my $products =
      $tokens->{navigation}->navigation_products->search_related('product')
      ->active;

    # Filter products based on facets in query params if there are any.
    # This loopy query stuff is terrible - should be a much better way
    # to do this but I haven't found one yet.
    if ( keys %query_facets ) {

        use Data::Dumper::Concise;

        print STDERR Dumper(%query_facets);

        my @skus = $products->get_column('product.sku')->all;

        foreach my $key ( keys %query_facets ) {

            @skus = $schema->resultset('Product')->search(
                {
                    -and => [
                        'me.sku' => { -in => \@skus },
                        -or      => [
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
                    columns => [ 'me.sku' ],
                    join  => [
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
            )->get_column('me.sku')->all;
        }

        $products = $schema->resultset('Product')->search(
            {
                'product.sku' => { -in => \@skus }
            },
            {
                alias => 'product'
            }
        );
    }

    # pager needs a paged version of the products result set

    my $paged_products = $products->limited_page( $tokens->{page}, $rows );
    my $pager = $paged_products->pager;
    $tokens->{pager} = $pager;

    # facets

    # TODO: counting facets needs review since this can be slow

    # start by grabbing the non-variant then variant facets into @facet_list
    my $cond = {
        'attribute.name' => { '!=' => undef }
    };

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
            { name        => 'attribute.name' },
            { value => 'attribute_value.value' },
            { title => 'attribute_value.title' },
            { count => { count => { distinct => 'product.sku' }} },
        ],
        group_by => [
            'attribute.name', 'attribute_value.value',
            'attribute_value.title', 'attribute_value.priority'
        ],
        order_by => [
            { -desc => 'attribute_value.priority' },
            { -asc  => 'attribute_value.title' },
        ]
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
            group_by =>
              [ 'attribute.name', 'attribute.title', 'attribute.priority', ],
        }
    );
    my $facet_group_rset2 = $products->search(
        { 'attribute.name' => { '!=' => undef } },
        {
            join       => { variants => { product_attributes => 'attribute' }},
            columns    => [],
            '+columns' => {
                name     => 'attribute.name',
                title    => 'attribute.title',
                priority => 'attribute.priority',
            },
            group_by =>
              [ 'attribute.name', 'attribute.title', 'attribute.priority', ],
        }
    );

    my $facet_group_rset =
      $facet_group_rset1->union($facet_group_rset2)->distinct('product.name')
      ->order_by('!product.priority,product.title');

    # now construct facets token
    my @facets;
    my %seen;
    while ( my $facet_group = $facet_group_rset->next ) {
        # it could in theory be possible to have two attributes with the same
        # name in the facet groups list so we skip if we've seen it before
        unless ( $seen{$facet_group->name} ) {

            my $data;
            my @results = grep { $_->{name} eq $facet_group->name } @facet_list;
            $data->{title} = $facet_group->get_column('title');

            $data->{values} = [ map {
                {
                    name  => $facet_group->name,
                    value => $_->{value},
                    title => $_->{title},
                    count => $_->{count}
                }
            } @results ];

            if ( defined $query_facets{$facet_group->name} ) {
                foreach my $value ( @{ $data->{values} } ) {
                    $value->{checked} = "yes"
                      if grep { $_ eq $value->{value} }
                      @{ $query_facets{ $facet_group->name } };
                }
            }
            push @facets, $data;
        }
    }
    $tokens->{facets} = \@facets;

    # product listing using paged_products result set

    my @products =
      $paged_products->listing( { users_id => session('logged_in_user_id') } )
      ->group_by( \@group_by )
      ->order_by( { "-$direction" => \@order_by } )->all;

    if ( $view eq 'grid' ) {
        my @grid;
        while ( scalar @products > 0 ) {
            push @grid, +{ row => [ splice @products, 0, 3 ] };
        }
        $tokens->{products} = \@grid;
    }
    else {
        $tokens->{products} = \@products;
    }

    # pagination

    if ( $pager->last_page > 1 ) {

        # we want pagination as there is more than one page of products

        my $first_page = 1;
        my $last_page  = $pager->last_page;

        if ( $pager->last_page > 5 ) {

            # more than 5 pages so we might need to start later than page 1

            if ( $pager->current_page <= 3 ) {
                $last_page = 5;
            }
            elsif (
                $pager->last_page - $pager->current_page <
                3 )
            {
                $first_page = $pager->last_page - 4;
            }
            else {
                $first_page = $pager->current_page - 2;
                $last_page = $pager->current_page + 2;
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
                  uri_for( $tokens->{navigation}->uri . '/' . $next,
                    \%query );
            }
        }
    }

    # breadcrumb and page name

    $tokens->{breadcrumb} = [$tokens->{navigation}->ancestors];
    $tokens->{"page-name"} = $tokens->{navigation}->name;

    # navigation siblings

    my $siblings_with_self = $tokens->{navigation}->siblings_with_self;

    my $siblings = [
        $siblings_with_self->columns( [qw/navigation_id uri name/] )
          ->add_columns(
            {
                count => $siblings_with_self->correlate('navigation_products')
                  ->search_related( 'product' )->active->count_rs->as_query
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

    # TODO: setting of selling_price and discount should not be in demo shop
    my $roles;
    if (logged_in_user) {
        $roles = user_roles;
        push @$roles, 'authenticated';
    }
    $tokens->{selling_price} = $product->selling_price( { roles => $roles } );

    $tokens->{discount} =
      int( ( $product->price  - $tokens->{selling_price} ) /
          $product->price *
          100 );

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
            rating   => $review->rating,
            author => $review->author,
            created  => $review->created->ymd,
            content  => $review->content,
          };
    }
    $tokens->{reviews} = \@reviews;
    $tokens->{"extra-js-file"} = 'product-page.js';
    $tokens->{breadcrumb} = $product->path;
    $tokens->{"page-name"} = $product->name;
};

get '/' => sub {
    template 'index';
};

ajax '/check_variant' => sub {

    # params should be sku and variant attributes only with optional quantity

    my %params = params;

    my $sku = $params{sku};
    delete $params{sku};

    my $quantity = $params{quantity};
    delete $params{quantity};
    $quantity = 1 unless defined $quantity;

    unless ( defined $sku ) {

        # sku not passed in params
        # TODO: do something here
    }

    my $product = shop_product($sku);
    unless ( $product ) {

        # product sku not found
        # TODO: do something here
    }

    try {
        $product = $product->find_variant( \%params );
    }
    catch {
        error "find_variant error: $_";
        # TODO: more to do than just return
        return undef;
    };

    unless ( $product ) {

        # variant not found
        # TODO: do something here
    }

    my $roles;
    if (logged_in_user) {
        $roles = user_roles;
        push @$roles, 'authenticated';
    }

    my $tokens;

    # TODO: refactoring alert: code duplication!

    $tokens->{product} = $product;

    $tokens->{selling_price} =
      $product->selling_price( { roles => $roles, quantity => $quantity } ),

    $tokens->{discount} =
      int( ( $product->price - $tokens->{selling_price} ) /
          $product->price *
          100 );

    my $in_stock = $product->quantity_in_stock;
    if ( defined $in_stock ) {
        if ( $in_stock == 0 ) {
            # TODO: we need something in the schema (product attributes?)
            # to set this token
            $tokens->{"product-availability"} = "Currently out of stock";
        }
        elsif ( $in_stock <= 10 ) {
            # TODO: maybe this ^^ number can be configured somewhere?
            $tokens->{"low-stock-alert"} = $in_stock;
        }
    }

    my $html = template "/fragments/product-price-and-stock", $tokens;
    # TODO: find out why this html gets wrapped into a complete page and
    # fix cleanly instead of doing the following (or else work out how
    # to send it as json that jquery will convert back to html).
    $html =~ s/^.+?div/<div/;
    $html =~ s|</body></html>$||;
    content_type('application/json');
    to_json({ html => $html });
};

shop_setup_routes;

true;
