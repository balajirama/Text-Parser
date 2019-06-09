
use strict;
use warnings;

use Test::More;
use Test::Exception;
use Text::Parser::Errors;

BEGIN {
    use_ok 'Text::Parser::ExAWK::Rule';
    use_ok 'Text::Parser';
}

throws_ok {
    my $rule = Text::Parser::ExAWK::Rule->new();
}
ExAWK(), 'Throws an error for no arguments';

lives_ok {
    my $rule = Text::Parser::ExAWK::Rule->new( if => '' );
    is( $rule->min_nf, 0,            'Min NF is 0' );
    is( $rule->action, 'return $0;', 'Default action' );
    $rule->add_precondition('$4 eq "SOMETHING"');
    is( $rule->min_nf, 4, 'Min NF changes to 4' );
    $rule->action('return $5');
    is( $rule->min_nf, 5, 'Min NF changes to 5' );
    $rule->action('return $3');
    is( $rule->min_nf, 4, 'Changes back to 4' );
    is( $rule->test,   0, 'Always returns 0 if no object passed' );
    my $parser = Text::Parser->new();
    dies_ok {
        $rule->test($parser);
    }
    'auto_split not enabled';
    $parser->auto_split(1);
    is( $rule->test($parser), 0, 'Test fails' );
}
'Empty rule starting with empty condition';

lives_ok {
    my $rule = Text::Parser::ExAWK::Rule->new( do => '' );
    is( $rule->min_nf,    0,   'Min NF is 0' );
    is( $rule->condition, '1', 'Default action' );
    $rule->add_precondition('$4 eq "SOMETHING"');
    is( $rule->min_nf, 4, 'Min NF changes to 4' );
    $rule->action('return $5');
    is( $rule->min_nf, 5, 'Min NF changes to 5' );
    $rule->action('return $3');
    is( $rule->min_nf, 4, 'Changes back to 4' );
    is( $rule->test,   0, 'Always returns 0 if no object passed' );
}
'Another empty rule with empty action';

lives_ok {
    my $rule = Text::Parser::ExAWK::Rule->new(
        if => '$1 eq "NAME:"',
        do => 'my (@fld) = $this->field_range(1, -1); return "@fld";',
    );

    my $parser = Text::Parser->new( auto_split => 1, );

    my @records = ();
    throws_ok {
        $rule->run;
    }
    ExAWK();
    $rule->run($parser) if $rule->test($parser);
}
'From the SYNOPSIS';

done_testing;

