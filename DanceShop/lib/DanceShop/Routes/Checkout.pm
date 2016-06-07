package DanceShop::Routes::Checkout;

use strict;
use warnings;

use Data::Transpose::Validator;

use Dancer2 ':syntax';
use Dancer2::Plugin::Interchange6;
use Dancer2::Plugin::Form;

# our logic - we got x checkout steps
# last step is saved in session
#
# current step exists ?
# if yes, check if we need to validate input
# if successful, go to next step
# if failure, stay on current step

any '/checkout' => sub {
    my $out;

    # Steps
    # 1 - Address
    # 2 - Shipping
    # 3 - Gift
    # 4 - Payment
    # 5 - Receipt

    my @steps = ({
                     name => 'address',
                     template => 'checkout-multipage-address',
                     validate => [
                         {
                             name => 'email',
                             validator => 'EmailValid',
                             required => 1,
                         },
                         {
                             name => 'first_name',
                             required => 1,
                         },
                         {
                             name => 'last_name',
                             required => 1,
                         },
                         {
                             name => 'city',
                             required => 1,
                         },
                     ],
                 },
                 {
                     name => 'shipping',
                     template => 'checkout-multipage-shipping',
                 },
                 {
                     name => 'gift',
                     template => 'checkout-multipage-gift',
                 },
                 {
                     name => 'payment',
                     template => 'checkout-multipage-payment',
                 },
                 {
                     name => 'receipt',
                     template => 'checkout-receipt',
                 }
             );

    if (exists config->{checkout_type} && config->{checkout_type} eq 'multi') {
        my $current_step = session('checkout_step');
        my %error_tokens;

        if ($current_step) {
            my $clean = 1;
            my $form = form('checkout-' . $current_step->{name});

            # validation ?
            if ($current_step->{validate}) {
                # validate input
                my $validator = Data::Transpose::Validator->new;

                $validator->prepare($current_step->{validate});
                my $clean = $validator->transpose({params});

                if ($clean) {
                    # ready for next step
                    $current_step = next_step(\@steps, $current_step);
                }
                else {
                    debug "Form errors on step ", $current_step->{name},
                        $validator->errors_hash;
                    for my $key (keys %{$validator->errors_hash}) {
                        $error_tokens{"${key}_status"} = 'has-error';
                    }
                }
            }
            else {
                $current_step = next_step(\@steps, $current_step);
            }
        }
        else {
            $current_step = next_step(\@steps, $current_step);
        }

        my $form = form('checkout-' . $current_step->{name});

        session checkout_step => $current_step;

        $out = template $current_step->{template},
            {cart => shop_cart,
             form => $form,
             %error_tokens,
         };
    }
    else {

        $out = template 'checkout', {cart => shop_cart};
    }

    return $out;
};

sub next_step {
    my ($steps_ref, $current_step) = @_;
    my $next_step = $steps_ref->[0];

    return $next_step if ! defined $current_step;

    for my $step (reverse @$steps_ref) {
        if ($current_step->{name} eq $step->{name}) {
            last;
        }
        $next_step = $step;
    }

    return $next_step;
}

1;
