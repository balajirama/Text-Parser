use strict;
use warnings;

package OneParser;
use Text::Parser::RuleSpec;
extends 'Text::Parser';
use Test::Exception;

lives_ok {
    applies_rule rule1 => ( if => 'uc($1) eq "HELLO"', );
}
'Makes some rule';

package AnotherParser;
use Text::Parser::RuleSpec;
extends 'Text::Parser';
use Test::Exception;

lives_ok {
    applies_rule my_rule => (
        if => '#something',
        do => '#something else',
    );
}
'Empty rule really';

package MyParser;
use Text::Parser::RuleSpec;
extends 'Text::Parser';
use Text::Parser::Errors;
use Test::Exception;

use AnotherParser;

throws_ok {
    applies_rule random_rule => ( before => 'OneParser/rule1', );
}
IllegalRuleNoIfNoAct();

throws_ok {
    applies_rule random_rule => (
        if     => 'uc($1) eq "HELLO"',
        before => 'NonExistent::Class/rule',
    );
}
RefToNonExistentRule();

throws_ok {
    applies_rule random_rule => (
        if     => '# something else',
        before => 'something',
        after  => 'something_else',
    );
}
OnlyOneOfBeforeOrAfter();

throws_ok {
    applies_rule random_rule => (
        if     => '# something else',
        before => 'something',
    );
}
BeforeOrAfterNeedsClassname();

throws_ok {
    applies_rule random_rule => (
        if     => '# something else',
        before => 'AnotherParser/my_rule',
    );
}
BeforeOrAfterOnlySuperclassRules();

lives_ok {
    applies_rule random_rule => (
        if     => '# something',
        before => 'OneParser/rule1',
    );
}
'Finally works';

package main;
use Test::More;


is_deeply(
    [ Text::Parser::RuleSpec->class_rule_order('MyParser') ],
    [ 'MyParser/random_rule', 'OneParser/rule1' ], 
    'set rules in correct order'
);

done_testing;
