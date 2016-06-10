package DanceShop::Routes::Search;

use strict;
use warnings;

use DanceShop::Search;
use Dancer2 appname => 'DanceShop';
use Dancer2::Plugin::Interchange6;

use Interchange::Search::Solr;

get '/search' => sub {
    my $q = param('q');
    my $tokens = {};

    my $solr = Interchange::Search::Solr->new(
        solr_url => config->{solr_url},
        global_conditions => {
            active => \"true",
        },
        facets => [],
    );

    $solr->search($q);

    my @products;
    my $rs = shop_schema->resultset('Product');

    for my $res (@{$solr->results}) {
        my $product = $rs->find($res->{sku});
        next unless $product;

        $res->{selling_price} = $product->selling_price;
        $res->{variant_count} = $product->variant_count;
        $res->{discount} = $product->discount_percent;
        $res->{quantity_in_stock} = $product->quantity_in_stock;
        $res->{average_rating} = 0;

        push @products, $res;
    }

    $tokens->{products} = \@products;

    template 'product-listing-list', $tokens;
};

1;

