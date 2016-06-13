package DanceShop::Filters::RatingClass;

=head1 NAME

DanceShop::Filters::RatingClass - product rating to class name converter

=head1 DESCRIPTION

Converts decimal product ratings into css class names required to display the
correct rating stars sprite.

Examples:

  1.2 => rating-10
  0.3 => rating-05
  4.8 => rating-50

=cut

use strict;
use warnings;

use base 'Template::Flute::Filter';

sub filter {
    my ( $self, $value ) = @_;
    return $value
      ? "rating-" . sprintf( "%02d", sprintf( "%.0f", $value * 2 ) * 5 )
      : "rating-0";
}

1;
