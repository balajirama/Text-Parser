
use strict;
use warnings;

package ParserClass;

use Test::Exception;
use Text::Parser::Error;
use Text::Parser::RuleSpec;

extends 'Text::Parser';

lives_ok {
    applies_rule empty_rule => ( if => '$1 eq "NOTHING"', do => 'print;' );
}
'Creates a basic rule';

package Parser2;

use Test::Exception;
use Text::Parser::Error;
use Text::Parser::RuleSpec;

extends 'Text::Parser';

lives_ok {
    applies_rule empty_rule => ( if => '$1 =~ /[*]/', do => 'print;' );
}
'Creates another basic rule';

package AnotherClass;

use Test::Exception;
use Text::Parser::Error;
use Text::Parser::RuleSpec;
extends 'ParserClass', 'Parser2';

lives_ok {
    applies_rule get_names => ( if => '$1 eq "NAME:"' );
}
'Creates a rule get_names';

lives_ok {
    applies_rule get_address => ( if => '$1 eq "ADDRESS:"', do => 'print;' );
}
'Creates a second rule';

package main;
use Test::Exception;
use Text::Parser::RuleSpec;
use Test::More;

BEGIN {
    use_ok 'Text::Parser::RuleSpec';
    use_ok 'Text::Parser::Error';
}

lives_ok {
    my $h = Text::Parser::RuleSpec->_class_rule_order;
    is_deeply(
        $h,
        {   ParserClass  => [qw(ParserClass/empty_rule)],
            Parser2      => ['Parser2/empty_rule'],
            AnotherClass => [
                qw(ParserClass/empty_rule Parser2/empty_rule AnotherClass/get_names AnotherClass/get_address)
            ]
        },
        'Has the right classes and rules'
    );
}
'Ran checks on Text::Parser::RuleSpec';

done_testing;
