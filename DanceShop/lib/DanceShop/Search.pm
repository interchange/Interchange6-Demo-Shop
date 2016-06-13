package DanceShop::Search;

use Data::Page;
use Dancer2::Core::Types qw/ArrayRef/;

use Moo;
extends 'Interchange::Search::Solr';
use namespace::clean;

has page_size => (
    is      => 'rw',
    default => sub { 20 },
);

has pager => (
    is      => 'rwp',
    lazy    => 1,
    default => sub {
        my $self  = shift;
        my $pager = Data::Page->new(
            total_entries    => $self->num_found,
            entries_per_page => $self->page_size,
        );
    },
);

has words => (
    is => 'rw',
    isa => ArrayRef,
    default => sub { [] },
);

1;
