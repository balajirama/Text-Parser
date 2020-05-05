use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN {
    use_ok 'Text::Parser';
}
my $parser = Text::Parser->new( track_indentation => 1 );
isa_ok( $parser, 'Text::Parser' );
$parser->add_rule( if => '$this->this_indent', do => '$2' );
lives_ok {
    $parser->read('t/names.txt');
}
'';
is_deeply( [ $parser->get_records ],
    ['BRIAN'], 'Only one record is indented' );

done_testing;
