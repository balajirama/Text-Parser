
use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN {
    use_ok 'Text::Parser';
}

lives_ok {
    my $parser = Text::Parser->new();
    $parser->END_rule(do => '');
    $parser->END_rule(do => '');
    $parser->add_rule( do => 'uc(${2+})', if => '$1 eq "NAME:"' );
    $parser->read('t/fullnames.txt');
    is( scalar( $parser->get_records ), 3, 'Got 3 items' );
    is_deeply(
        [ $parser->get_records ],
        [ 'BALAJI RAMASUBRAMANIAN', 'ELIZABETH E. MILLER', 'BRIAN FOY' ],
        'Matches perfectly'
    );
}
'does not die';

done_testing;
