use utf8;

package DanceShop::Routes;

=encoding utf8

=head1 NAME

DanceShop::Routes - routes for DanceShop

=cut

use warnings;
use strict;

use Dancer2 appname => 'DanceShop';
use Dancer2::Plugin::Auth::Extensible;
use Dancer2::Plugin::Interchange6;
use POSIX 'ceil';
use Try::Tiny;

use DanceShop::Routes::Account;
use DanceShop::Routes::Checkout;
use DanceShop::Routes::Search;

=head1 ROUTES

See also: L<DanceShop::Routes::Checkout> L<DanceShop::Routes::Search>

=head2 get /

=cut

get '/' => sub {
    my $tokens = {};

    # 3 offers

    $tokens->{offers} = DanceShop::offers(3);

    # need 6 random products not already in offers

    my @skus = map { $_->canonical_sku || $_->sku } @{ $tokens->{offers} };

    $tokens->{products} = [
        shop_product->search(
            {
                'me.sku' => {
                    -in => shop_product->search(
                        {
                            'active'        => 1,
                            'canonical_sku' => undef,
                            'sku'           => { -not_in => \@skus },
                        }
                    )->rand(6)->get_column('sku')->as_query
                },
                'media.label'     => [ '', 'low', 'thumb' ],
                'media_type.type' => 'image',
            },
            {
                prefetch => { media_products => 'media' },
                join     => { media_products => { media => 'media_type' } },
                order_by => 'media.priority',
            }
        )->listing->all
    ];

    # brands

    my @brands = shop_navigation->search( { scope => 'brands', active => 1 },
        { order_by => 'name' } )->hri->all;

    my $brands_per_col = ceil( @brands / 6 );

    while ( my @col = splice( @brands, 0, $brands_per_col ) ) {
        push @{ $tokens->{brands} }, +{ col => \@col };
    }

    $tokens->{'extra-js-file'} = 'index.js';
    template 'index', $tokens;
};

=head2 get /add-review/:sku

=cut

get '/add-review/:sku' => sub {
    my $tokens;
    my $sku = route_parameters->get('sku');
    my $form = form('review');

    # $sku = param('sku');
    
    debug "Review for $sku.";
    
    my $product = shop_product($sku);

    if ($product && $product->active) {
        # preparing tokens
        $tokens->{product} = $product;
        $tokens->{breadcrumb} = $product->path;
        debug "Product: ", $tokens->{product}->name;
    }
    template 'add-review', $tokens;
};

=head2 post /add-review/:sku

=cut

post '/add-review/:sku' => sub {
    my $tokens;
    my $sku = route_parameters->get('sku');
    my $form = form('review');
    
    # $sku = param('sku');
    
    debug "New Review for $sku with values: ", $form->values;
    
    my $product = shop_product($sku);

    if ($product && $product->active) {
        # create message
        my $x = $product->add_to_reviews({
            rating => '',
        });

        debug "M out: ", $x;
        # send email to moderator
    }
    template 'add-review', $tokens;
};

=head2 ajax /check_variant

=cut

post '/check_variant' => sub {

    if (! request->is_ajax) {
        return undef;
    }

    # params should be sku and variant attributes only with optional quantity

    my %params = body_parameters->flatten;

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

    my $html = template "/fragments/product-price-and-stock", $tokens,
      { layout => undef };

    # TODO: find out why this html gets wrapped into a complete page and
    # fix cleanly instead of doing the following (or else work out how
    # to send it as json that jquery will convert back to html).
    $html =~ s/^.+?div/<div/;
    $html =~ s|</body></html>$||;
    content_type('application/json');
    to_json( { html => $html } );
};

true;
