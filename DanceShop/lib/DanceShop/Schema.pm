package DanceShop::Schema;

use base 'Interchange6::Schema';

our $VERSION = 1;

__PACKAGE__->load_components( 'Schema::Config' );

Interchange6::Schema->load_namespaces(
    default_resultset_class => 'ResultSet',
    result_namespace        => [ 'Result', '+PerlDance::Schema::Result' ],
    resultset_namespace     => [ 'ResultSet', '+PerlDance::Schema::ResultSet' ],
);

1;
