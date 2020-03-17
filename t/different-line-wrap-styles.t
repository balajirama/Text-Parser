
use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN {
    use_ok('Text::Parser');
    use_ok('Text::Parser::Errors');
}

lives_ok {
    my $parser = Text::Parser->new( line_wrap_style => 'spice' );
    isa_ok $parser, 'Text::Parser';
    is( $parser->multiline_type, 'join_last', 'Correctly set unwrapper' );
    $parser->add_rule( if => 'substr($1, 0, 1) eq "*"', dont_record => 1 );
    $parser->add_rule(
        if => 'uc(substr($1, 0, 1)) eq "M"',
        do => 'chomp; $_;'
    );
    $parser->multiline_type(undef);
    $parser->read('t/example-2.sp');
    is_deeply [ $parser->get_records ],
        [ "Minst net1", ],
        'Spice line-wrap settings, but changed back to undef';
    $parser->line_wrap_style('spice');
    $parser->read('t/example-2.sp');
    is_deeply( [ $parser->get_records ],
        ['Minst net1 net2 net3 net4 nmos l=0.09u w=0.13u'] );
};

lives_ok {
    my $parser = Text::Parser->new( line_wrap_style => 'trailing_backslash' );
    isa_ok $parser, 'Text::Parser';
    is( $parser->multiline_type, 'join_next', 'Correctly set unwrapper' );
    $parser->read('t/continued.txt');
    is_deeply(
        [ $parser->get_records ],
        [   "Some text on this line is being continued on the next line with the back-slash character. This is more readable than having the whole text on one single line.\n"
        ]
    );
};

lives_ok {
    my $parser = Text::Parser->new( line_wrap_style => 'slurp' );
    isa_ok $parser, 'Text::Parser';
    is( $parser->multiline_type, 'join_last', 'Correctly set unwrapper' );
    $parser->read('t/example.plaintext.txt');
    is( scalar( $parser->get_records ), 1, 'slurped in the whole file' );
};

lives_ok {
    my $parser = Text::Parser->new( line_wrap_style => 'just_next_line' );
    isa_ok $parser, 'Text::Parser';
    is( $parser->multiline_type, 'join_last', 'Correctly set unwrapper' );
    $parser->read('t/example-wrapped.txt');
    is scalar( $parser->get_records ), 3,
        'slurped in the whole paragraph as one record';
};

lives_ok {
    my $parser = Text::Parser->new( line_wrap_style => 'custom' );
    isa_ok $parser, 'Text::Parser';
    is( $parser->multiline_type, undef, 'Correctly set unwrapper' );
    lives_ok {
        $parser->read('t/example-custom-line-wrap.txt');
    };
    $parser->multiline_type('join_last');
    is( $parser->multiline_type, 'join_last', 'Correctly set unwrapper' );
    dies_ok {
        $parser->read('t/example-custom-line-wrap.txt');
    }, UndefLineUnwrapRoutine();
    dies_ok {
        $parser->custom_line_unwrap_routines();
    }, BadCustomUnwrapCall();
    dies_ok {
        $parser->custom_line_unwrap_routines( 1, 2, 3, 4 );
    }, BadCustomUnwrapCall();
    dies_ok {
        $parser->custom_line_unwrap_routines( is_wrapped => 2, 3, 4 );
    }, BadCustomUnwrapCall();
    dies_ok {
        $parser->custom_line_unwrap_routines( unwrap_routine => 2, 3, 4 );
    }, BadCustomUnwrapCall();
    dies_ok {
        $parser->custom_line_unwrap_routines(
            unwrap_routine => 2,
            is_wrapped     => 4
        );
    }, BadCustomUnwrapCall();
    my $unwrap_routine = sub {
        my ( $self, $last_line, $this_line ) = @_;
        chomp $last_line;
        $last_line =~ s/\s*$//g;
        $this_line =~ s/^[~]\s*//g;
        "$last_line $this_line";
    };
    $parser->custom_line_unwrap_routines(
        is_wrapped => sub {
            my ( $self, $this_line ) = @_;
            return 0 if not defined $self->multiline_type;
            $this_line =~ /^[~]/;
        },
        unwrap_routine => $unwrap_routine,
    );
    $parser->_unwrap_routine(undef);
    dies_ok {
        $parser->read('t/example-custom-line-wrap.txt');
    }, UndefLineUnwrapRoutine();
    $parser->_unwrap_routine($unwrap_routine);
    $parser->read('t/example-custom-line-wrap.txt');
    is_deeply [ $parser->get_records ],
        [
        "This is a long line that is wrapped around with a custom character - the tilde. It is unusual, but hey, we're showing an example.\n"
        ], 'Custom line-wrapped 1';
    $parser->line_wrap_style(undef);
    $parser->read('t/example-custom-line-wrap.txt');
    is_deeply [ $parser->get_records ],
        [
        "This is a long line that is wrapped around with a custom\n",
        "~ character - the tilde. It is unusual, but hey, we\'re\n",
        "~ showing an example.\n",
        ],
        'You can unset line-unwrapping';
};

lives_ok {
    my $parser = Text::Parser->new( line_wrap_style => undef );
};

done_testing;
