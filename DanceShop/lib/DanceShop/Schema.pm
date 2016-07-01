package DanceShop::Schema;

use base 'Interchange6::Schema';

our $VERSION = 1;

__PACKAGE__->load_components( 'Schema::Config' );

Interchange6::Schema->load_namespaces(
    default_resultset_class => 'ResultSet',
    result_namespace        => [ 'Result', '+DanceShop::Schema::Result' ],
    resultset_namespace     => [ 'ResultSet', '+DanceShop::Schema::ResultSet' ],
);

1;
