use utf8;
package DanceShop;

=encoding utf8

=head1 NAME

DanceShop - base Demo Shop for Interchange 6

=head1 VERSION

0.001

=cut

our $VERSION = '0.001';

use Dancer ':syntax';
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Interchange6;
use Dancer::Plugin::Interchange6::Routes;

use DanceShop::Routes::Checkout;

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
      int( ( $tokens->{selling_price} - $product->price ) /
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
            $tokens->{"low-stock-alert"} = $in_stock;
        }
    }
};

get '/' => sub {
    template 'index';
};

shop_setup_routes;

true;
