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
use Dancer::Plugin::Ajax;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Interchange6;
use Dancer::Plugin::Interchange6::Routes;
use DanceShop::Routes::Checkout;
use DateTime;
use Try::Tiny;

set session => 'DBIC';
set session_options => {schema => schema};

hook 'before_layout_render' => sub {
    my $tokens = shift;

    $tokens->{cart} = cart;

    my $nav = shop_navigation->search(
        {
            type => 'nav',
            parent_id => undef,
        },
        {
            order_by => { -asc => 'priority'},
        }
    );
    while (my $record = $nav->next) {
        push @{$tokens->{'nav-' . $record->scope}}, $record;
    };
};

hook 'before_navigation_display' => sub {
    my $tokens = shift;
    
    my %querystring_params = params('query');

    my $routes_config = config->{plugin}->{'Interchange6::Routes'};

    # TODO: view should be stored in session so that it is preserved across
    # requests as user navigates around shop. For now this is at least useful
    # for testing
    my $view = $querystring_params{view};
    if ( defined $view ) {
        undef $view unless grep { $_ eq $view } (qw/grid list simple compact/);
    }
    unless ( defined $view ) {
        $view = $routes_config->{navigation}->{default_view} || 'list';
    }
    $tokens->{"navigation-view-$view"} = 1;

    # TODO: another things that should perhaps be stored in session is rows
    # this should probably also be handled in plugin
    # NOTE: this is not currently used
    my $rows = $querystring_params{rows};
    if ( defined $rows ) {
        undef $rows unless $rows =~ /^\d+$/;
    }
    unless ( defined $rows ) {
        $rows = $routes_config->{navigation}->{records} || 10;
    }
    $tokens->{breadcrumb} = [$tokens->{navigation}->ancestors];
    $tokens->{"page-name"} = $tokens->{navigation}->name;
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
