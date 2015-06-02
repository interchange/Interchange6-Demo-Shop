package DanceShop::SearchResults;

use 5.010001;
use strict;
use warnings;

use Moo;
use MooX::Types::MooseLike::Base qw(HashRef);

use POSIX qw/ceil/;
use List::Util qw(first);

=head1 ATTRIBUTES

=head2 routes_config

Hash reference from L<Dancer::Plugin::Interchange6::Routes> plugin
configuration (required).

=cut

has routes_config => (
    is       => 'ro',
    isa      => HashRef,
    required => 1,
);

=head2 query

Query parameters from HTTP request.

=cut

has query => (
    is       => 'ro',
    isa      => HashRef,
    required => 1,
);

=head2 tokens

Template tokens (hash reference, required).

=cut

has tokens => (
    is       => 'ro',
    isa      => HashRef,
    required => 1,
);

=head2 current_view

Returns name of current view.

=over

=item writer: set_current_view

=back

=cut

has current_view => (
    is     => 'ro',
    writer => 'set_current_view',
);

=head2 current_sorting

Returns the name of the current sort order, after calling C<select_sorting>.

=over

=item writer: set_current_sorting

=back

=cut

has current_sorting => (
    is     => 'ro',
    writer => 'set_current_sorting'
);

=head2 set_current_sorting

Returns the name of the current sorting direction, after calling C<select_sorting>.

=over

=item writer: set_current_sorting_direction

=back

=cut

has current_sorting_direction => (
    is     => 'ro',
    writer => 'set_current_sorting_direction'
);

=head2 views

Returns list of views.

=cut

has views => (
    is      => 'rw',
    default => sub {
        return [
            {
                name  => 'grid',
                title => 'Grid',
                icon  => 'icon-view-grid',
            },
            {
                name  => 'list',
                title => 'List',
                icon  => 'icon-view-list',
            },
            {
                name  => 'simple',
                title => 'Simple',
                icon  => 'icon-view-simple',
            },
            {
                name  => 'compact',
                title => 'Compact',
                icon  => 'icon-view-compact',
            },
        ];
    },
);

=head1 METHODS

=head2 select_view

determine which view to display

=cut

sub select_view {
    my ($self)        = @_;
    my $routes_config = $self->routes_config;
    my $tokens        = $self->tokens;
    my @views         = @{ $self->views };
    my $view          = $self->query->{view};

    if (   !defined $view
        || !grep { $_ eq $view } map { $_->{name} } @views )
    {
        $view = $routes_config->{navigation}->{default_view} || 'grid';
    }
    $self->set_current_view($view);

    $tokens->{"navigation-view-$view"} = 1;

    my $view_index = first { $views[$_]->{name} eq $view } 0 .. $#views;
    $views[$view_index]->{active} = 'active';
    $tokens->{views} = \@views;
}

=head2 select_rows

Set C<per_page_iterator> token ('show X per page' dropdown) and C<per_page>
token (rows to display for this request).

C<per_page_iterator> values are taken from
$self->routes_config->{navigation}->{records} with default being 10. For grid
view this is rounded up to first higher value that is divisible by three.

=cut

sub select_rows {
    my ($self)        = @_;
    my $routes_config = $self->routes_config;
    my $tokens        = $self->tokens;

    # rows (products per page)

    # default rows per page from config
    my $config_rows = $routes_config->{navigation}->{records} || 10;

    my $rows = $self->query->{rows};

    if ( !defined $rows || $rows !~ /^\d+$/ ) {
        $rows = $config_rows;
    }

    my @rows_iterator;
    if ( $self->current_view eq 'grid' ) {
        $config_rows = ceil( $config_rows / 3 ) * 3;
        $rows        = ceil( $rows / 3 ) * 3;
    }
    $tokens->{per_page_iterator} =
      [ map { +{ value => $config_rows * $_ } } 1 .. 4 ];
    $tokens->{per_page} = $rows;
}

=head2 select_sorting

=cut

sub select_sorting {
    my ($self) = @_;
    my $tokens = $self->tokens;
    my $query  = $self->query;

    my @order_by_iterator = (
        { value => 'priority',       label => 'Position' },
        { value => 'average_rating', label => 'Rating' },
        { value => 'selling_price',  label => 'Price' },
        { value => 'name',           label => 'Name' },
        { value => 'sku',            label => 'SKU' },

    );
    $tokens->{order_by_iterator} = \@order_by_iterator;

    my $order     = $query->{order};
    my $direction = $query->{dir};

    # maybe set default order(_by)
    if (   !defined $order
        || !grep { $_ eq $order } map { $_->{value} } @order_by_iterator )
    {
        $order = 'priority';
    }
    $tokens->{order_by} = $order;

    # maybe set default direction
    if ( !defined $direction || $direction !~ /^(asc|desc)/ ) {
        if ( $order =~ /^(average_rating|priority)$/ ) {
            $direction = 'desc';
        }
        else {
            $direction = 'asc';
        }
    }

    # asc/desc arrow
    if ( $direction eq 'asc' ) {
        $tokens->{reverse_order} = 'desc';
        $tokens->{order_by_class} = 'icon icon-arrow-up';
    }
    else {
        $tokens->{reverse_order} = 'asc';
        $tokens->{order_by_class} = 'icon icon-arrow-down';
    }
    $self->set_current_sorting($order);
    $self->set_current_sorting_direction($direction);
    return $order;
}

=head2 sorting_for_solr

=cut

sub sorting_for_solr {
    my $self    = shift;
    my $sorting = $self->current_sorting;
    if ( $sorting and $sorting eq 'priority' ) {
        return 'score';
    }
    else {
        return $sorting;
    }
}

=head2 BUILD

Calls L</select_view>, L</select_sorting> and L</select_rows> and also sets
the token C<views>.

=cut

sub BUILD {
    my $self = shift;
    $self->select_view;
    $self->select_sorting;
    $self->tokens->{views} = $self->views;
    $self->select_rows;
}

1;
