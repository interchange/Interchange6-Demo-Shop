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

    my %query = params('query');

    my $routes_config = config->{plugin}->{'Interchange6::Routes'};

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
    $rows = ceil($rows/3)*3 if ( $view eq 'grid' );

    # order

    my $order     = $query{order};
    my $direction = $query{dir};
    if (   !defined $order
        || !grep { $_ eq $order } (qw/priority price name sku/) )
    {
        $order     = 'priority';
        $direction = 'desc';
    }
    my @order_by = ( "product.$order" );
    unshift( @order_by, "me.priority" ) if ( $order eq 'priority' ); 

    if ( !defined $direction || $direction !~ /^(asc|desc)/ ) {
        $direction = 'asc';
    }

    # products and pager

    my $products =
      $tokens->{navigation}->navigation_products->search_related('product')
      ->active->limited_page( $tokens->{page}, $rows );

    $tokens->{pager} = $products->pager;

    my @products =
      $products->listing( { users_id => session('logged_in_user_id') } )
      ->group_by( [ 'product.sku', 'inventory.quantity', @order_by ] )
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

    # breadcrumb and page name

    $tokens->{breadcrumb} = [$tokens->{navigation}->ancestors];
    $tokens->{"page-name"} = $tokens->{navigation}->name;

    # navigation siblings

    my $siblings_with_self = $tokens->{navigation}->siblings_with_self;
    my $siblings = [
        $siblings_with_self->search(
            undef,
            {
                columns => [qw/navigation_id uri name/],
                '+columns' => {
                    count =>
                      $siblings_with_self->correlate('navigation_products')
                      ->search_related( 'product', { active => 1, }, )
                      ->count_rs->as_query
                },
                order_by => [ { -desc => 'priority' }, { -asc => 'name' } ],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator'
            }
        )->all
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
