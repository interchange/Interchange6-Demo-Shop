package DanceShop::Data::DataPop;

use strict;
use warnings;

use Interchange6::Schema;
use Interchange6::Schema::Populate::CountryLocale;
use Interchange6::Schema::Populate::StateLocale;

use Dancer ':script';
use Dancer::Plugin::Interchange6;

use Term::ProgressBar;

use Tie::IxHash;
use Try::Tiny;

my $shop_schema = shop_schema;

use utf8;

sub create_db{
    print "Creating database.\n";
    shop_schema->deploy({add_drop_table => 1,
        producer_args => {
            mysql_version => 5,
        },
    });
}

sub pop_users{
    my $no_users = shift; 
    #ceating and populating user data
    for(0...$no_users){
        my $user = DanceShop::Data::DataGen::users();
        my $user_obj = shop_user->create($user);
    }
}

sub pop_attributes{
    # create color attribute
    foreach my $color (@{DanceShop::Data::DataGen::colors()}) {
        $shop_schema->resultset('Attribute')
          ->search( { name => 'color' }, { rows => 1 } )
          ->single->add_to_attribute_values($color);
    }
    
    # create size attribute
        my $size_data = {
            name             => 'size',
            title            => 'Size',
            type             => 'variant',
            priority         => 1,
            attribute_values => DanceShop::Data::DataGen::size()
        };
        my $size_att = $shop_schema->resultset('Attribute')->create($size_data);
    
    foreach my $height ( @{DanceShop::Data::DataGen::height()} ) {
        $shop_schema->resultset('Attribute')
          ->search( { name => 'height' }, { rows => 1 } )
          ->single->add_to_attribute_values($height);
    }
}

sub pop_products{
    my ($no_products, $no_colors) = @_;
    
    #generating products data
    my $progress = Term::ProgressBar->new ({count => $no_products, name => 'Products', ETA   => 'linear'});
    my $so_far;
    my $skus = DanceShop::Data::DataGen::uniqe_varchar($no_products);
    my @products;
    foreach(@{$skus}){
        my $product = DanceShop::Data::DataGen::products($_);
        my $variants = DanceShop::Data::DataGen::variants($product, $no_colors);
        try {
            $shop_schema->resultset('Product')->create($product)
              ->add_variants( @{$variants} );
            $progress->update(++$so_far);
        };
    }
}

sub pop_navigation{
    
    my @navs = $shop_schema->resultset('Navigation')->search(
        {
            scope => 'menu-main',
            uri   => { like => '%/%' },
        },
    )->all;

    my $products = $shop_schema->resultset('Product')->search(
        {
            sku           => { 'not like' => 'os%' },
            canonical_sku => undef,
        }
    );

    my $nav_progress = Term::ProgressBar->new(
        { count => $products->count, name => 'Navigation', ETA => 'linear' } );

    my $count;
    while (my $product = $products->next) {
        $count++;
        my $ran = DanceShop::Data::DataGen::rand_int(0, $#navs);
        my $nav = $navs[$ran];
        $shop_schema->resultset('NavigationProduct')->create(
            {
                sku           => $product->sku,
                navigation_id => $nav->navigation_id
            }
        );
        # also add to parent
        $shop_schema->resultset('NavigationProduct')->create(
            {
                sku           => $product->sku,
                navigation_id => $nav->parent->navigation_id
            }
        );
        $nav_progress->update ($count);
    }
};

sub pop_orders{
    my $no_orders = shift;
    my @users= $shop_schema->resultset('User')->search()->all;
    my $nav_progress = Term::ProgressBar->new ({count => $#users+1, name => 'Orders', ETA   => 'linear'});
    my $counter;
    foreach(@users){
        $counter++;
        my $count = 0;
        while($count < $no_orders){
            $count++;
            DanceShop::Data::DataGen::orders($_->id);
        }
        $nav_progress->update ($counter);
    }
};
1;
