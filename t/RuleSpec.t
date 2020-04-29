
use strict;
use warnings;

package ParserClass;

use Test::Exception;
use Text::Parser::Errors;
use Text::Parser::RuleSpec;

extends 'Text::Parser';

lives_ok {
    applies_rule empty_rule => ( if => '$1 eq "NOTHING"', do => 'print;' );
}
'Creates a basic rule';

package AnotherClass;

use Test::Exception;
use Text::Parser::Errors;
use Text::Parser::RuleSpec;
extends 'ParserClass';

throws_ok {
    applies_rule;
}
SpecMustHaveName();

throws_ok {
    applies_rule {};
}
SpecMustHaveName();

throws_ok {
    applies_rule if => '$1 eq "NAME:"';
}
SpecRequiresHash();

throws_ok {
    applies_rule 'failing_rule';
}
SpecRequiresHash();

lives_ok {
    applies_rule get_names => ( if => '$1 eq "NAME:"' );
}
'Creates a rule get_names';

throws_ok {
    applies_rule get_names => ( if => '$1 eq "EMAIL:"' );
}
NameRuleUniquely();

lives_ok {
    applies_rule get_address => ( if => '$1 eq "ADDRESS:"', do => 'print;' );
}
'Creates a second rule';

throws_ok {
    applies_rule get_DOB => ('something random');
}
SpecRequiresHash();

throws_ok {
    applies_rule get_DOB => ();
}
SpecRequiresHash();

throws_ok {
    disables_superclass_rules [];
}
BadDisableRulespecArg();

package main;
use Test::Exception;
use Text::Parser::RuleSpec;
use Test::More;

BEGIN {
    use_ok 'Text::Parser::RuleSpec';
    use_ok 'Text::Parser::Errors';
}

throws_ok {
    applies_rule if => '$1 eq "NAME:"';
}
MainCantApplyRule();

throws_ok {
    applies_rule get_names => ( if => '$1 eq "NAME:"' );
}
MainCantApplyRule();

throws_ok {
    disables_superclass_rules 'ParserClass/empty_rule';
}
MainCantCallRulespecFunc();

lives_ok {
    my $h = Text::Parser::RuleSpec->_class_rule_order;
    is_deeply(
        $h,
        {   ParserClass  => [qw(ParserClass/empty_rule)],
            AnotherClass => [
                qw(ParserClass/empty_rule AnotherClass/get_names AnotherClass/get_address)
            ]
        },
        'Has the right classes and rules'
    );
}
'Ran checks on Text::Parser::RuleSpec';

done_testing;
