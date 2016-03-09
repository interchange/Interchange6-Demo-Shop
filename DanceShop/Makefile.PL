use strict;
use warnings;
use ExtUtils::MakeMaker;

# Normalize version strings like 6.30_02 to 6.3002,
# so that we can do numerical comparisons on it.
my $eumm_version = $ExtUtils::MakeMaker::VERSION;
$eumm_version =~ s/_//;

WriteMakefile(
    NAME         => 'DanceShop',
    AUTHOR       => q{Stefan Hornburg (Racke) <racke@linuxia.de>},
    VERSION_FROM => 'lib/DanceShop.pm',
    ABSTRACT     => 'Interchange6 Open Source Shop Machine Demo Shop',
    (
        $eumm_version >= 6.47
        ? ( 'LICENSE' => 'perl' )
        : ()
    ),
    MIN_PERL_VERSION => '5.014000',
    PL_FILES         => {},
    PREREQ_PM        => {
        'Class::Load'                     => 0,
        'Test::More'                      => 0,
        'YAML'                            => 0,
        'Dancer'                          => '1.3142',
        'Dancer::Plugin::Cache::CHI'      => '1.4.0',
        'Dancer::Plugin::Interchange6'    => '0.101',
        'Dancer::Plugin::PageHistory'     => '0.102',
        'Template::Flute'                 => '0.0184',
        'Dancer::Template::TemplateFlute' => '0.0142',
        'namespace::clean'                => 0,
        'Number::Format'                  => 0,          # currency filter
        'Moo'                             => '2.000001',
        'Type::Tiny'                      => '1.000005',
        'URL::Encode'                     => 0,
        'Interchange::Search::Solr'      => '0.12',

        # validation
        'Data::Transpose' => '0.0011',
        'Email::Valid'    => 0,

        # development
        'Plack::Middleware::Debug::Dancer::TemplateVariables' => 0,
        'Plack::Middleware::Debug::Dancer::Version' => 0,
        'Plack::Middleware::Debug::DBIC::QueryLog' => 0,

        # default deployment
        'Starman' => 0,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES    => 'DanceShop-*' },
);
