
use strict;
use warnings;

package AnotherClass;

use Test::Exception;
use Text::Parser::Errors;
use Text::Parser::RuleSpec;

dies_ok {
    applies_rule if => '$1 eq "NAME:"';
}
SpecMustHaveName();

lives_ok {
    applies_rule get_names => ( if => '$1 eq "NAME:"' );
} 'Creates a rule get_names';

dies_ok {
    applies_rule get_names => (
        if => '$1 eq "EMAIL:"'
    );
} NameRuleUniquely();

package main;
use Test::Exception;
use Text::Parser::RuleSpec;
use Test::More;


BEGIN {
    use_ok 'Text::Parser::RuleSpec';
    use_ok 'Text::Parser::Errors';
}

dies_ok {
    applies_rule if => '$1 eq "NAME:"';
}
SpecMustHaveName();

dies_ok {
    applies_rule get_names => ( if => '$1 eq "NAME:"' );
}
MainCantApplyRule();

done_testing;
