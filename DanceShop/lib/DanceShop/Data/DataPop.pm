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
	my @colors = @{Flowers::Data::DataGen::colors()};
	$shop_schema->resultset('Attribute')->delete;
	my $color_data = {name => 'color', title => 'Color', type => 'variant', priority => 2,
			  AttributeValue => \@colors};
	my $color_att = $shop_schema->resultset('Attribute')->create($color_data);
	
	# create size attribute
	my $size_data = {name => 'size', title => 'Size', type => 'variant', priority => 1,
			AttributeValue => Flowers::Data::DataGen::size()};
	my $size_att = $shop_schema->resultset('Attribute')->create($size_data);
	
	# create height attribute
	my $height_data = {name => 'height', title => 'Height', type => 'variant', priority => 0,
			AttributeValue =>Flowers::Data::DataGen::height()};
	my $height_att = $shop_schema->resultset('Attribute')->create($height_data);
}

sub pop_products{
	my ($no_products, $no_colors) = @_;
	$shop_schema->resultset('Product')->search(
	{
		'canonical_sku' => { '!=', undef },
	})->delete_all;
	$shop_schema->resultset('Product')->delete_all;
	
	#generating products data
	my $progress = Term::ProgressBar->new ({count => $no_products, name => 'Products', ETA   => 'linear'});
	my $so_far;
	my $skus = Flowers::Data::DataGen::uniqe_varchar($no_products);
	my @products;
	$shop_schema->resultset('Product')->delete;
	foreach(@{$skus}){
		$so_far++;
		my $product = Flowers::Data::DataGen::products($_);
		my $variants = Flowers::Data::DataGen::variants($product, $no_colors);
		my $product_g = $shop_schema->resultset('Product')->create($product)->add_variants(@{$variants});
		push (@products, $product);
		$progress->update ($so_far);
	}
	return \@products;
}

sub pop_navigation{
	# populate navigation table
	scalar $shop_schema->populate('Navigation', Flowers::Data::DataGen::navigation());
	# create navigation_id hash

	my @nav = $shop_schema->resultset('Navigation')->search(
	{
		'scope' => 'menu-main',
	},
	)->all;
	
	my $products =  $shop_schema->resultset('Product')->search(
	{
		'canonical_sku' => undef,
	});
	my $nav_progress = Term::ProgressBar->new ({count => $products ->count, name => 'Navigation', ETA   => 'linear'});
	my $count;
	$shop_schema->resultset('NavigationProduct')->delete;
	while (my $product = $products->next) {
		$count++;
		my $ran = Flowers::Data::DataGen::rand_int(0, $#nav);
		$shop_schema->resultset('NavigationProduct')->create({sku => $product->sku,navigation_id => $nav[$ran]->navigation_id});
		$nav_progress->update ($count);
	}
};

sub pop_orders{
	my $no_orders = shift;
	$shop_schema->resultset('Order')->delete_all;
	my @users= $shop_schema->resultset('User')->search()->all;
	my $nav_progress = Term::ProgressBar->new ({count => $#users+1, name => 'Orders', ETA   => 'linear'});
	my $counter;
	foreach(@users){
		$counter++;
		my $count = 0;
		while($count < $no_orders){
			$count++;
			Flowers::Data::DataGen::orders($_->id);
		}
		$nav_progress->update ($counter);
	}
};
1;
