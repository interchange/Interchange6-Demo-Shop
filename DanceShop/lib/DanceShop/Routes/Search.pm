package DanceShop::Routes::Search;

use strict;
use warnings;

use DanceShop::Search;
use Dancer ':syntax';

use Interchange::Search::Solr;

get '/search' => sub {
    my $q = param('q');
    my $tokens = {};

    my $sr = Interchange::Search::Solr->new(
        solr_url => config->{solr_url},
        global_conditions => {
            active => \"true",
        },
        facets => [],
    );

    $sr->search($q);

    $tokens->{products} = $sr->results;

    template 'product-listing-list', $tokens;
};

1;

