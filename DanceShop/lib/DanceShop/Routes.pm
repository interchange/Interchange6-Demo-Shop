use utf8;

package DanceShop::Routes;

=encoding utf8

=head1 NAME

DanceShop::Routes - routes for DanceShop

=cut

use warnings;
use strict;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Interchange6;
use POSIX 'ceil';
use Try::Tiny;

use DanceShop::Routes::Checkout;

=head1 ROUTES

See also: L<DanceShop::Routes::Checkout>

=head2 get /

=cut

get '/' => sub {
    my $tokens = {};

    $tokens->{offers} = DanceShop::offers(3);

    # need four random products not already in offers

    my @skus = map { $_->canonical_sku || $_->sku } @{ $tokens->{offers} };

    my $products = shop_product->search(
        {
            'me.active'        => 1,
            'me.canonical_sku' => undef,
            'me.sku'           => { -not_in => \@skus },
        },
        {
            join => 'price_modifiers',
        }
    );

    # possible role-based pricing
    my $user = logged_in_user;
    if ($user) {
        $products =
          $products->with_lowest_selling_price( { users_id => $user->id } );
    }
    else {
        $products = $products->with_lowest_selling_price;
    }

    $tokens->{products} = [ $products->rand(6)->with_quantity_in_stock->all ];

    # brands

    my @brands = shop_navigation->search( { scope => 'brands', active => 1 },
        { order_by => 'name' } )->hri->all;

    my $brands_per_col = ceil( @brands / 6 );

    while ( my @col = splice( @brands, 0, $brands_per_col ) ) {
        push @{ $tokens->{brands} }, +{ col => \@col };
    }

    template 'index', $tokens;
};

=head2 ajax /check_variant

=cut

ajax '/check_variant' => sub {

    # params should be sku and variant attributes only with optional quantity

    my %params = params;

    my $sku = delete $params{sku};

    my $quantity = delete $params{quantity};
    $quantity = 1 unless defined $quantity;

    # nothing to do if no sku or no variant attributes
    return undef unless ( defined $sku && %params );

    my $product = shop_product->single( { sku => $sku, active => 1 } );
    if ( !$product ) {
        error "check_variant did not find product: $sku";
        return undef;
    }

    try {
        $product = $product->find_variant( \%params );
    }
    catch {
        error "find_variant error: $_";

        # TODO: more to do than just return
        return undef;
    };

    if ( !$product ) {

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
    to_json( { html => $html } );
};

true;
