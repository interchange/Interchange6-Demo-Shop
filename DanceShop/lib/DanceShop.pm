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
use DateTime;

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

hook 'before_navigation_display' => sub {
    my $tokens = shift;
    
    my %querystring_params = params('query');

    # FIXME: view should be stored in session so that it is preserved across
    # requests as user navigates around shop. For now this is at least useful
    # for testing
    my $route_config = config->{plugin}->{'Interchange6::Routes'};
    my $view = $querystring_params{view};
    if ( defined $view ) {
        undef $view unless grep { $_ eq $view } (qw/grid list simple compact/);
    }
    unless ( defined $view ) {
        $view = $route_config->{navigation}->{default_view} || 'list';
    }
    $tokens->{"navigation-view-$view"} = 1;

    # FIXME: following still needs thought & fixing...
    # we need to add selling_price to the products token
    # TODO: this should be handled in schema/plugin especially since
    # the plugin might pass a resultset or an array of products depending
    # on the template engine in use

#    my $roles;
#    if ( logged_in_user ) {
#        $roles = user_roles;
#        push @$roles, 'authenticated';
#    }
#    push @$roles, 'anonymous';

#    my $dtf = shop_schema->storage->datetime_parser;
#    my $today = $dtf->format_datetime(DateTime->today);
#    my $rset = $tokens->{products}->search(
#        {
#            'role.name'                => { -in => $roles },
#            'price_modifiers.quantity' => 1,
#            'price_modifiers.start_date' => [ undef, { '<=', $today } ],
#            'price_modifiers.end_date'   => [ undef, { '>=', $today } ],
#        },
#        {
#            join => { 'price_modifiers' => 'role' },
#            '+select' => [ { min => 'price_modifiers.price' } ],
#            '+as' => [ 'selling_price' ],
#            group_by => [ 'product.sku' ],
#        }
#    );
#    $rset = $tokens->{products}->as_subselect_rs->search(
#        {},
#    );
    #$rset = $tokens->{products}->with_selling_price($roles);
    #$tokens->{products} = $rset;
    #info $rset->count;
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
            $tokens->{"product-availability"} = "Currently out of stock";
        }
        elsif ( $in_stock <= 10 ) {
            $tokens->{"low-stock-alert"} = $in_stock;
        }
    }

    # TODO: hopefully this will not be necessary once TF supports dotted
    # notation for accessors in list param
    my @reviews;
    my $reviews = $product->top_reviews;
    while ( my $review = $reviews->next ) {
        my $name = $review->author->name;
        $name = 'anonymous' if ( !$name || $name =~ /^\s*$/ );
        push @reviews,
          {
            rating   => $review->rating,
            reviewer => $name,
            created  => $review->created->ymd,
            content  => $review->content,
          };
    }
    $tokens->{reviews} = \@reviews;
};

get '/' => sub {
    template 'index';
};

shop_setup_routes;

true;
