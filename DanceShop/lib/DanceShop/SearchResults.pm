package DanceShop::SearchResults;

use List::Util qw(first);
use Dancer2::Core::Types qw(ArrayRef HashRef InstanceOf Int Object is_Str Str);
use POSIX qw/ceil/;

use Moo;
use namespace::clean;

=head1 ATTRIBUTES

=head2 routes_config

Hash reference from L<Dancer2::Plugin::Interchange6::Routes> plugin
configuration (hash reference, required).

=cut

has routes_config => (
    is       => 'ro',
    isa      => HashRef,
    required => 1,
);

=head2 session

Dancer2 session. Required.

=cut

has session => (
    is       => 'ro',
    isa      => InstanceOf['Dancer2::Core::Session'],
    required => 1,
);

=head2 query

Query parameters from HTTP request (hash reference, required).

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

=head2 default_rows

The default number of rows defined by ->{navigation}->{records} in
L</routes_config> or 10 if not defined. When L</view> is C<grid> then
this value is increased to the next multiple of 3 if it is not already
a multiple of 3.

=cut

has default_rows => (
    is  => 'lazy',
    isa => Int,
);

sub _build_default_rows {
    my $self = shift;

    my $default_rows = $self->routes_config->{navigation}->{records};
    $default_rows = defined $default_rows ? $default_rows : 10;
    if ( $self->view eq 'grid' ) {
        $default_rows = ceil( $default_rows / 3 ) * 3;
    }
    return $default_rows;
}

=head2 view

Returns name of current view.

Defaults to L</routes_config>->{navigation}->{default_view} or C<grid>.

=cut

has view => (
    is  => 'lazy',
    isa => Str,
);

sub _build_view {
    my $self          = shift;
    my $routes_config = $self->routes_config;
    my @views         = @{ $self->views };
    my $session_view  = $self->session->read('search_view');
    my $view          = $self->query->{view} || $session_view;

    if (   !defined $view
        || !grep { $_ eq $view } map { $_->{name} } @views )
    {
        $view = $routes_config->{navigation}->{default_view} || 'grid';
    }

    $self->session->write(search_view => $view) if $view && $session_view ne $view;

    return $view;
}

=head2 order_by_iterator

=cut

has order_by_iterator => (
    is  => 'lazy',
    isa => ArrayRef [HashRef],
);

sub _build_order_by_iterator {
    my @order_by_iterator = (
        { value => 'priority',       label => 'Position' },
        { value => 'average_rating', label => 'Rating' },
        { value => 'selling_price',  label => 'Price' },
        { value => 'name',           label => 'Name' },
        { value => 'sku',            label => 'SKU' },

    );
    return \@order_by_iterator;
}

=head2 rows

Returns the number of rows (products) to display.

=cut

has rows => (
    is  => 'lazy',
    isa => Int,
);

sub _build_rows {
    my $self = shift;

    my $session_rows = $self->session->read('search_rows');
    my $rows = $self->query->{rows} || $session_rows;

    # we don't check whether rows is undefined since we don't want a user
    # to be able to set a value of 0 unless we allow that in our config
    if ( !$rows || $rows !~ /^\d+$/ ) {
        $rows = $self->default_rows;
    }

    # round up to next power of 3 for grid view
    if ( $self->view eq 'grid' ) {
        $rows = ceil( $rows / 3 ) * 3;
    }

    $self->session->write(search_rows => $rows) unless $session_rows eq $rows;

    return $rows;
}

=head2 order_by

Returns the name of the current sort column. Defaults to <priority>.

=cut

has order_by => (
    is  => 'lazy',
    isa => Str,
);

sub _build_order_by {
    my $self  = shift;
    my $session_order = $self->session->read('search_order');
    my $order = $self->query->{order} || $session_order;
    if (
           !defined $order
        || !grep { $_ eq $order }
        map      { $_->{value} } @{ $self->order_by_iterator }
      )
    {
        $order = 'priority';
    }

    $self->session->write(search_order => $order) unless $session_order eq $order;

    return $order;
}

=head2 order_direction

Returns the name of the current sort direction.

=cut

has order_direction => (
    is  => 'lazy',
    isa => sub {
        die "bad sort_order"
          unless ( is_Str( $_[0] ) && $_[0] =~ /^(a|d)/ );
    },
);

sub _build_order_direction {
    my $self = shift;
    my $session_direction = $self->session->read('search_direction');
    my $direction = $self->query->{dir} || $session_direction;

    if ( !defined $direction || $direction !~ /^(asc|desc)/ ) {
        if ( $self->order_by =~ /^(average_rating|priority)$/ ) {
            $direction = 'desc';
        }
        else {
            $direction = 'asc';
        }
    }

    $self->session->write( search_direction => $direction )
      unless $session_direction eq $direction;

    return $direction;
}

=head2 views

Returns list of views.

=cut

has views => (
    is      => 'ro',
    isa     => ArrayRef [HashRef],
    default => sub {
        +[
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


=head2 sorting_for_solr

=cut

sub sorting_for_solr {
    my $self    = shift;
    my $sorting = $self->order_by;
    if ( $sorting and $sorting eq 'priority' ) {
        return 'score';
    }
    else {
        return $sorting;
    }
}

=head2 BUILD

Adds the following tokens to L</tokens>:

  order_by
  order_by_iterator
  per_page
  per_page_iterator
  views
  reverse_order
  order_by_class

=cut

sub BUILD {
    my $self   = shift;
    my $tokens = $self->tokens;

    $tokens->{order_by} = $self->order_by;

    $tokens->{order_by_iterator} = $self->order_by_iterator;

    if ( $self->default_rows ) {

        # rows == 0 means we show all rows so only set these next two tokens
        # if we have some rows

        $tokens->{per_page} = $self->rows;

        $tokens->{per_page_iterator} =
          [ map { +{ value => $self->default_rows * $_ } } 1 .. 4 ];
    }

    # add 'active' to the current view from $self->views
    my @views = @{ $self->views };
    my $view_index = first { $views[$_]->{name} eq $self->view } 0 .. $#views;
    $views[$view_index]->{active} = 'active';
    $tokens->{views} = \@views;

    if ( $self->order_direction =~ /^a/ ) {
        $tokens->{reverse_order}  = 'desc';
        $tokens->{order_by_class} = 'icon icon-arrow-up';
    }
    else {
        $tokens->{reverse_order}  = 'asc';
        $tokens->{order_by_class} = 'icon icon-arrow-down';
    }
}

1;
