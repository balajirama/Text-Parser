use strict;
use warnings;

package Base1;
use Text::Parser::RuleSpec;
extends 'Text::Parser';
use Test::Exception;

lives_ok {
    applies_rule rule1 => ( if => '# is_rule1?', );

    applies_rule rule2 => ( if => '# is_rule2?', );
}
'Base1 rules loaded';

package Base2;
use Text::Parser::RuleSpec;
extends 'Text::Parser';
use Test::Exception;

lives_ok {
    applies_rule rule1 => ( if => '# is_rule1', );

    applies_rule rule2 => ( if => '# is_rule2', );
}
'Base2 rules loaded';

package Blend1;
use Text::Parser::RuleSpec;
extends 'Base2';
use Test::Exception;

lives_ok {
    applies_cloned_rule 'Base1/rule1' => ( if => '# is_cloned_rule1', );
}
'Cloned Base1/rule1';

package main;

use Test::More;

use Text::Parser::RuleSpec;



done_testing;
