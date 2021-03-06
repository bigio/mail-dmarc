use strict;
use warnings;

use Data::Dumper;
use Test::Exception;
use Test::More;

use lib 'lib';
use Mail::DMARC::PurePerl;
use Mail::DMARC::Report;

eval "use DBD::SQLite 1.31";
if ($@) {
    plan( skip_all => 'DBD::SQLite not available' );
    exit;
}
            
eval "use XML::SAX::ParserFactory;";
if ($@) {
    plan( skip_all => 'XML::SAX::ParserFactory not available' );
    exit;
}

eval "use XML::Validator::Schema;";
if ($@) {
    plan( skip_all => 'XML::Validator::Schema not available' );
    exit;
}

my $dmarc = Mail::DMARC::PurePerl->new();

$dmarc->source_ip('66.128.51.165');
$dmarc->envelope_to('recipient.example.com');
$dmarc->envelope_from('dmarc-nonexist.tnpi.net');
$dmarc->header_from('mail-dmarc.tnpi.net');
$dmarc->dkim([
        {
        domain      => 'tnpi.net',
        selector    => 'jan2015',
        result      => 'fail',
        human_result=> 'fail (body has been altered)',
    }
]);
$dmarc->spf([
        {   domain => 'tnpi.net',
            scope  => 'mfrom',
            result => 'pass',
        },
        {
            scope  => 'helo',
            domain => 'mail.tnpi.net',
            result => 'fail',
        },
    ]);

my $policy = $dmarc->discover_policy;
my $result = $dmarc->validate($policy);
$dmarc->save_aggregate();

my $store = $dmarc->{'report'}->{'store'};
$store->{SQL}->config('t/mail-dmarc.ini');

die 'Not using test store' if $store->{'SQL'}->{'config'}->{'report_store'}->{'dsn'} ne 'dbi:SQLite:dbname=:memory:';

my $a = $store->{'SQL'}->query('UPDATE report SET begin=begin-86400, end=end-86400 WHERE id=1');

my $agg = $store->retrieve_todo()->[0];

test_against_schema();

done_testing();
exit;

sub test_against_schema {

    $agg->metadata->report_id(1);

    my $xml = $agg->as_xml();
    lives_ok( sub{
        my $validator = XML::Validator::Schema->new(file => 'share/rua-schema.xsd');
        my $parser = XML::SAX::ParserFactory->parser(Handler => $validator);
        $parser->parse_string( $xml );
    }, 'Check schema' );
    # print $xml;

};

