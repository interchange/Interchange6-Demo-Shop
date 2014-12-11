package DanceShop::Data::DataGen;

use strict;
use warnings;

use Interchange6::Schema;
use parent 'DBIx::Class::ResultSet';

__PACKAGE__->load_components('Helper::ResultSet::Random');

use Dancer ':script';
use Dancer::Plugin::Interchange6;

#Random data generators
use Data::Faker;
use Data::Generate qw{parse};
use Acme::MetaSyntactic;

use utf8;

my $fake = Data::Faker->new;
my $meta = Acme::MetaSyntactic->new;
my $shop_schema = shop_schema;

sub users {
    my $name     = $fake->first_name;
    my $lastname = $fake->last_name;
    my $domain   = $fake->domain_name;
    my $password = parse(q{VC(10) [A-Z][1-14].[a-z][2579]{4}[A-Z][14]{2}})
      ->get_unique_data(1);

    my $rset_countries = $shop_schema->resultset('Country');
    my $country        = $rset_countries->search(
        undef,
        {
            rows => 1,
            offset => int( rand( $rset_countries->count ) ),
        }
    )->single;

    my $states_id;
    if ( $country->show_states ) {
        my $rset_states = $shop_schema->resultset('State')->search(
            {
                country_iso_code => $country->country_iso_code,
            }
        );
        $states_id = $rset_states->search(
            undef,
            {
                rows => 1,
                offset => int( rand( $rset_states->count ) ),
            }
        )->single->states_id;
    }

    my $user = {
        username => lc($name) . "@" . $domain,
        email    => lc($name) . "@" . $domain,
        password => $password,
        first_name => $name,
        last_name => $lastname,
        addresses => [
            {
                type             => 'shipping',
                first_name       => $name,
                last_name        => $lastname,
                address          => $fake->street_address,
                postal_code      => $fake->us_zip_code,
                city             => $fake->city,
                country_iso_code => $country->country_iso_code,
                states_id        => $states_id,
                phone            => $fake->phone_number,
            },
            {
                type             => 'billing',
                first_name       => $fake->first_name,
                last_name        => $fake->last_name,
                address          => $fake->street_address,
                postal_code      => $fake->us_zip_code,
                city             => $fake->city,
                country_iso_code => $country->country_iso_code,
                states_id        => $states_id,
                phone            => $fake->phone_number,
            }
        ]
    };
    return $user;
}

sub products {
    my $sku = shift;

    #generate product parents
    my ( $name, $uri, $short_description, $description ) = data($sku);
    my $product = {
        sku               => $sku,
        name              => $name,
        short_description => $short_description,
        description       => $description,
        price             => price(),
        uri               => $uri,
        canonical_sku     => undef,
        weight            => weight()
    };
    return $product;
}

#generate product variants
sub variants {
    my ( $product, $no_colors ) = @_;
    my $max_children_no = $no_colors || rand_int( 0, $#{ colors() } - 1 );
    my @variants;
    my $colors = unique_colors($max_children_no);
    foreach ( @{$colors} ) {
        my $color = $_;
        my $sizes = size();
        for my $size ( @{$sizes} ) {
            my $size_letter = lc( substr( $size->{'title'}, 0, 1 ) );
            my $sku =
              join( "-", $product->{'sku'}, $color->title, $size_letter );
            my $variant = {
                sku   => $sku,
                color => $color->value,
                size  => $size->{'value'},
                name  => join( " ",
                    $color->title, $size->{'title'}, $product->{'name'} ),
                uri =>
                  join( "-", $product->{'uri'}, $size_letter, $color->value ),
            };
            push( @variants, $variant );
        }
    }
    return \@variants;
}

sub navigation {
    my @navigation = (
        [
            'roses', 'nav', 'menu-main', 'Flower', '', '0', '0', undef, '0',
            '0', '0'
        ],
        [
            'birthday', 'nav', 'menu-main', 'Birthday', '', '0', '0', undef,
            '0', '0', '0'
        ],
        [
            'flowers', 'nav', 'menu-main', 'Flowers', '', '0', '0', undef, '0',
            '0', '0'
        ],
        [
            'plants', 'nav', 'menu-main', 'Plants',
            '',       '0',   '0',         undef,
            '0',      '0',   '0'
        ],
        [
            'occasions', 'nav', 'menu-main', 'Occasions', '', '0', '0', undef,
            '0', '0', '0'
        ],
        [
            'sympathy', 'nav', 'menu-main', 'Sympathy', '', '0', '0', undef,
            '0', '0', '0'
        ],
        [
            'gift-baskets', 'nav', 'menu-main', 'Gift Baskets', '', '0', '0',
            undef, '0', '0', '0'
        ],
        [
            'specialty-gifts', 'nav', 'menu-main', 'Specialty Gifts',
            '', '0', '0', undef, '0', '0', '0'
        ],
        [
            'same-day', 'nav', 'menu-main', 'Same Day', '', '0', '0', undef,
            '0', '0', '0'
        ],
        [
            'sale', 'nav', 'menu-main', 'Sale', '', '0',
            '0',    undef, '0',         '0',    '0'
        ],
        [
            'login', 'auth', 'top-login', 'Login', '', '0',
            '0',     undef,  '0',         '0',     '0'
        ],
        [
            'registration', 'nav', 'top-right', 'Sign Up', '', '0', '0', undef,
            '0', '0', '0'
        ],
        [
            'forum', 'nav', 'top-left', 'Forum', '', '0',
            '0',     undef, '0',        '0',     '0'
        ],
        [
            'about-us', 'nav', 'top-left', 'About Us',
            '',         '0',   '0',        undef,
            '0',        '0',   '0'
        ],
        [
            'orders', 'nav', 'top-left', 'Orders', '', '0',
            '0',      undef, '0',        '0',      '0'
        ],
        [
            'customer-service', 'nav', 'top-left', 'Customer Service',
            '', 'customer-service', '0', undef, '0', '0', '0'
        ],
        [
            'logout', 'auth', 'top-logout', 'Logout', '', '', '0', undef, '0',
            '0', '0'
        ]
    );

    my $navigation = [
        [
            'uri',         'type',          'scope', 'name',
            'description', 'template',      'alias', 'parent_id',
            'priority',    'product_count', 'active'
        ],
        @navigation,
    ];
    return $navigation;
}

sub colors {
    my $color_names = [$meta->name('colours', 0)];
    my @colors;
    my $rset = $shop_schema->resultset('AttributeValue');
    foreach ( @{$color_names} ) {
        next if $rset->search({value=>$_})->count;
        my $color->{value} = $_;
        ($color->{title} = $_) =~ s/_/ /g;
        push( @colors, $color );
    }
    @colors = sort { $a->{'value'} cmp $b->{'value'} } @colors;
    return \@colors;
}

sub size {
    my $size = [
        { value => 'small',  title => 'Small',  priority => 2 },
        { value => 'medium', title => 'Medium', priority => 1 },
        { value => 'large',  title => 'Large',  priority => 0 },
    ];
    return $size;
}

sub orders {
    my $userid           = shift;
    my $shipping_address = shop_address->search(
        {
            'users_id' => $userid,
            'type'     => 'shipping',
        }
    )->first;

    my $billing_address = shop_address->search(
        {
            'users_id' => $userid,
            'type'     => 'billing',
        }
    )->first;

    unless ( $shipping_address && $billing_address ) {
        return 1;
    }

    my $products = $shop_schema->resultset('Product')->search(
        {
            'canonical_sku' => undef,
        }
    );

    my ( @orderlines, $count );
    my ( $weight,     $subtotal );
    while ( my $product = $products->next ) {
        my $rand_int = rand_int( 1, $products->count - 1 );
        $count++;
        if ( $count == $rand_int ) {
            my $rand = rand_int( 3, 20 );
            $weight   = $product->weight;
            $subtotal = $product->price * $rand;
            push @orderlines,
              {
                sku               => $product->sku,
                order_position    => $_,
                name              => $product->name,
                short_description => $product->short_description,
                description       => $product->description,
                weight            => $product->weight,
                quantity          => $rand,
                price             => $product->price,
                subtotal          => $subtotal,
              };
        }
        $subtotal += $subtotal || 0;
        $weight   += $weight   || 0;
    }
    my $date = $fake->date_this_year;
    $date =~ s/T/ /g;
    my $order_data = shop_order->create(
        {
            order_date            => $date,
            users_id              => $userid,
            billing_addresses_id  => $billing_address->id,
            shipping_addresses_id => $shipping_address->id,
            weight                => $weight,
            subtotal              => $subtotal,
            Orderline             => \@orderlines,
        }
    );

    $date =~ s/\D//g;
    $order_data->update(
        {
                order_number => 'UID'
              . $userid
              . $date . 'OID'
              . $order_data->orders_id,
        }
    );
}

sub height {
    my $height = [
        { value => '10', title => '10cm' },
        { value => '20', title => '20cm' },
        { value => '30', title => '30cm' },
        { value => '40', title => '40cm' },
        { value => '50', title => '50cm' },
    ];
    return $height;
}

sub data {
    my $sku = shift;
    my ( $name, $uri, $short_description, $description );
    $name = join( " ", map $fake->meta, 1..3 );
    $name =~ s/_/ /g;
    $uri = join( "-", $sku, $name );
    $uri =~ s/ /-/g;
    $name = ucfirst($name);
    $short_description = join( " ", $name, map $fake->meta, 1..20 );
    $short_description =~ s/_/ /g;
    $description = join(" ", $meta->name('loremipsum', 0));
    return ( $name, $uri, $short_description, $description );
}

sub price {
    my ($price);
    $price = parse(q{ FLOAT (9) [0-9]{3} . [1-9]{2}})->get_unique_data(1);
    return sprintf( "%.2f", $price->[0] );
}

sub weight {
    my ($weight);
    $weight = parse(q{INT [1-99]})->get_unique_data(1);
    return $weight->[0];
}

sub rand_int {
    my ( $x, $y ) = @_;
    my $rand = int( rand( $y - $x + 1 ) ) + $x;
    return $rand;
}

sub unique_colors {
    my $array_size = shift;
    my @colors     = $shop_schema->resultset('Attribute')->search(
        {
            'name' => 'color',
        },
    )->search_related('attribute_values');

    print STDERR "\n" . scalar @colors . "\n";
    my $rand =
      parse( "INT [0-" . ( $#colors - 1 ) . "]" )->get_unique_data($array_size);
    my @unique_colors;
    foreach ( @{$rand} ) {
        push( @unique_colors, $colors[$_] );
    }
    @unique_colors = sort { $a->value cmp $b->value } @unique_colors;
    return \@unique_colors;
}

sub uniqe_varchar {
    my $count = shift;

    #generate uniqe varchar list
    my $data    = parse(q{VC(10) [A-Z][1-14][a-z][2579]{4}[A-Z][14]{2}});
    my $freedom = $data->get_degrees_of_freedom();
    if ( $freedom < $count ) {
        die "Max unique value count exceeded. Please set value below $freedom.";
    }
    my $varchars = $data->get_unique_data($count);
    return $varchars;
}
1;
