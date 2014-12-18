package DanceShop::Filters::SellingPrice;

=head1 NAME

DanceShop::Filters::SellingPrice - filter for possibly undef selling_price

=head1 DESCRIPTION

The filter inherits from L<Template::Flute::Filter::Currency> and but instead
of throwing an exception when the price is undefined it instead returns undef.

=cut

use strict;
use warnings;

use Moo;
extends 'Template::Flute::Filter::Currency';

around filter => sub {
    my ( $orig, $self, $amount ) = @_;
    return undef unless defined $amount;
    $orig->( $self, $amount );
};

1;
