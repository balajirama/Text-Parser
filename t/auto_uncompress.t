use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN { use_ok 'Text::Parser'; }

my $parser = Text::Parser->new( auto_uncompress => 1, );
$parser->add_rule( if => '$1 eq "Email:"', do => 'return $2;' );

foreach my $fname (qw(t/example.txt.gz t/account.txt)) {
    $parser->read($fname);
    is( scalar( $parser->get_records ), 3, "3 records found in $fname" );
}

throws_ok {
    $parser->read('t/non-text-as-text.jpg');
}
'Text::Parser::Error', 'Is neither text nor compressed';

done_testing;
