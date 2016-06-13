package DanceShop::Paging;

use Dancer2::Core::Types qw(InstanceOf HashRef);
use URI;

use Moo;
use namespace::clean;

has pager => (
    is => 'rw',
    isa => InstanceOf['Data::Page'],
    required => 1,
);

has uri => (
    is => 'rw',
    required => 1,
);

has query => (
    is => 'rw',
    isa => HashRef,
);

sub page_list {
    my $self = shift;
    my $pager = $self->pager;
    my $uri = $self->uri;
    my $current = $pager->current_page;
    my $first_page = 1;
    my $last_page  = $pager->last_page;
    my %query;

    if ( $pager->last_page > 5 ) {
        # more than 5 pages so we might need to start later than page 1
        if ( $pager->current_page <= 3 ) {
            $last_page = 5;
        }
        elsif (
            $pager->last_page - $pager->current_page <
             3 )
            {
                $first_page = $pager->last_page - 4;
            }
        else {
            $first_page = $pager->current_page - 2;
            $last_page = $pager->current_page + 2;
        }
    }

    my @pages = map {
       +{
           page => $_,
           uri  => $_ == $pager->current_page
           ? undef
           : $self->uri_for( "$uri/$_" ),
           active => $_ == $pager->current_page ? " active" : undef,
         }
    } $first_page .. $last_page;

    return \@pages;
}

sub previous_uri {
    my $self = shift;
    my $pager = $self->pager;

    if ($pager->previous_page) {
        return $self->uri_for($self->uri . '/' . $pager->previous_page);
    }

    return undef;
}

sub next_uri {
    my $self = shift;
    my $pager = $self->pager;

    if ($pager->next_page) {
        return $self->uri_for($self->uri . '/' . $pager->next_page);
    }

    return undef;
}

sub uri_for {
    my ($self, $path) = @_;
    my $uri = URI->new;

    $uri->path($path);
    $uri->query_form($self->query);

    return $uri->canonical;
}

1;
