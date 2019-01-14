use strict;
use warnings;

package MultBasic;
use parent 'Text::Parser';

use Role::Tiny::With;
with 'Text::Parser::Multiline::Typical';
with 'Text::Parser::Multiline';

package main;

use Test::More;
use Test::Exception;
use Test::Output;

lives_ok {
    my $mpars = MultBasic->new();
    $mpars->read('t/data.txt');
    is_deeply(
        [ $mpars->get_records() ],
        ["1\n2 3\n 4\n five\nsix seven\n"],
        'Expected output'
    );
    is( $mpars->lines_parsed(), 5, 'Five lines parsed' );
}
'No errors in reading file';

done_testing;
