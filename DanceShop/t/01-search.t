#!perl

use strict;
use warnings;
use Test::More;
use Interchange::Search::Solr;

my $solr_url;

if ($ENV{SOLR_URL}) {
    $solr_url = $ENV{SOLR_URL};
}
else {
    plan skip_all => "Please set environment variable SOLR_URL.";
}

my $solr = Interchange::Search::Solr->new(
    solr_url => $solr_url,
    facets   => [],
    global_conditions => {active => \"true"}
);

$solr->search([]);

my $results = $solr->results;
ok($results->[0], 'get results return from empty search');


$solr = Interchange::Search::Solr->new(
    solr_url => $solr_url,
    facets   => [qw/category/],
    global_conditions => {active => \"true"}
);
$solr->search([]);
$results = $solr->results;

ok (scalar(@$results) == 10, 'get results return')
    || diag "No result and get error: $results";

ok($results->[0]->{sku}, 'get results return from empty category search');


done_testing;