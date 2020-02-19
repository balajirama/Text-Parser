
use strict;
use warnings;

package MyParser;

use Text::Parser::RuleSpec;
use Test::Exception;
extends 'Text::Parser';

lives_ok {
    applies_rule get_emails => (
        if => '$1 eq "EMAIL:"',
        do => '$2;'
    );

}
'Creates a rule';

package main;
use Test::More;
use Test::Exception;

lives_ok {
    my $parser = MyParser->new();
    $parser->read('t/example-compare_native_perl-1.txt');
    is_deeply(
        [ $parser->get_records() ],
        [qw(brian@webhost.net darin123@yahoo.co.uk aud@audrey.io)],
        'All emails collected'
    );
}
'Main code works file';
done_testing;
