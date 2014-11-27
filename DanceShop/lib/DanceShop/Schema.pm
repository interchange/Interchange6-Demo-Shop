package DanceShop::Schema;

use strict;
use warnings;

use Interchange6::Schema::Result::Product;

Interchange6::Schema::Result::Product->add_columns(
    min_age => {
        data_type   => "integer",
        is_nullable => 1,
    }
);

1;
