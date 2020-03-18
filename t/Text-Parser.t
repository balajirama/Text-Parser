use strict;
use warnings;

use Test::More;
use Test::Exception;
use Text::Parser::Errors;

BEGIN { use_ok 'Text::Parser'; }
BEGIN { use_ok 'FileHandle'; }

my $fname = 'text-simple.txt';

my $pars;
throws_ok { $pars = Text::Parser->new('balaji'); }
SingleParamsToNewMustBeHashRef(), 'single non-hashref arg';
throws_ok { $pars = Text::Parser->new('balaji'); }
'Moose::Exception::SingleParamsToNewMustBeHashRef', 'single non-hashref arg';
throws_ok { $pars = Text::Parser->new( balaji => 1 ); }
'Moose::Exception::Legacy', 'Throws an exception for bad keys';
throws_ok { $pars = Text::Parser->new( multiline_type => 'balaji' ); }
'Moose::Exception::ValidationFailedForInlineTypeConstraint',
    'Throws an exception for bad value';
lives_ok { $pars = Text::Parser->new( multiline_type => undef ); }
'Improve coverage';
$pars = Text::Parser->new();
isa_ok( $pars, 'Text::Parser' );
is( $pars->filename(), undef, 'No filename specified so far' );

is( $pars->multiline_type, undef, 'Not a multi-line parser' );
is( $pars->multiline_type('join_next'),
    'join_next', 'I can set this to join_next if need be' );
lives_ok {
    $pars->multiline_type(undef);
}
'No error when trying to reset multiline_type';

lives_ok {
    $pars->read('t/example-split.txt');
    is( scalar $pars->get_records, 5, '5 lines' );
    $pars->read('t/example-wrapped.txt');
    is( scalar $pars->get_records, 21, '21 lines' );
}
'No errors on reading with this';

throws_ok {
    is( $pars->multiline_type('join_next'),
        'join_next', 'Make it another type of Multiline Parser' );
    $pars->read('t/example-wrapped.txt');
}
'Text::Parser::Errors::UnexpectedEof',
    'No errors on changing multiline_type, but error in reading';

lives_ok {
    is( $pars->multiline_type('join_last'),
        'join_last', 'Change back type of Multiline Parser' );
    $pars->read('t/example-wrapped.txt');
    is( scalar $pars->get_records, 1, '1 line' );
}
'No errors on reading these lines';

$pars = Text::Parser->new();

lives_ok { is( $pars->filehandle(), undef, 'Not initialized' ); }
'This should not die, just return undef';
throws_ok { $pars->filehandle('bad argument'); }
'Moose::Exception::ValidationFailedForInlineTypeConstraint',
    'filehandle() will take only a GLOB or FileHandle input';
throws_ok { $pars->filename( { a => 'b' } ); }
'Moose::Exception::ValidationFailedForInlineTypeConstraint',
    'filename() will take only string as input';
throws_ok { $pars->filename('') }
'Text::Parser::Errors::InvalidFilename', 'Empty filename string';
throws_ok { $pars->filename($fname) }
'Text::Parser::Errors::InvalidFilename', 'No file by this name';
throws_ok { $pars->read( bless {}, 'Something' ); }
'Moose::Exception::ValidationFailedForInlineTypeConstraint',
    'filehandle() will take only a GLOB or FileHandle input';
throws_ok { $pars->read($fname); }
'Text::Parser::Errors::InvalidFilename',
    'Throws exception for non-existent file';

lives_ok { $pars->read(); } 'Returns doing nothing';
is( $pars->lines_parsed, 0, 'Nothing parsed' );
is_deeply( [ $pars->get_records ], [], 'No data recorded' );
is( $pars->last_record, undef, 'No records' );
is( $pars->pop_record,  undef, 'Nothing on stack' );

lives_ok { $pars->read(''); } 'Reads no file ; returns doing nothing';
is( $pars->filename(),     undef, 'No file name still' );
is( $pars->lines_parsed(), 0,     'Nothing parsed again' );

SKIP: {
    skip 'Tests not meant for root user', 2 unless $>;
    skip 'Tests wont work on MSWin32',    2 unless $^O ne 'MSWin32';
    open OFILE, ">t/unreadable.txt";
    print OFILE "This is unreadable\n";
    close OFILE;
    chmod 0200, 't/unreadable.txt';
    throws_ok { $pars->filename('t/unreadable.txt'); }
    'Text::Parser::Errors::FileNotReadable', 'This file cannot be read';
    is( $pars->filename(), undef, 'Still no file has been read so far' );
    unlink 't/unreadable.txt';
}

throws_ok { $pars->filename('t/example.gzip.txt.gz'); }
'Text::Parser::Errors::FileNotPlainText', 'This file is binary';
is( $pars->filename(), undef, 'Still no file has been read so far' );

my $content = "This is a file with one line\n";
lives_ok { $pars->filename( 't/' . $fname ); } 'Now I can open the file';
lives_ok { $pars->read; } 'Reads the file now';
is_deeply( [ $pars->get_records ], [$content], 'Get correct data' );
is( $pars->lines_parsed, 1,             '1 line parsed' );
is( $pars->last_record,  $content,      'Worked' );
is( $pars->pop_record,   $content,      'Popped' );
is( $pars->lines_parsed, 1,             'Still lines_parsed returns 1' );
is( $pars->filename(),   't/' . $fname, 'Last file read' );

open OUTFILE, ">example";
lives_ok { $pars->filehandle( \*OUTFILE ); }
'Convert even a write filehandle into a read FileHandle object.';
is( $pars->filename(), undef, 'Last file read is not available anymore' );
print OUTFILE "Simple text";
close OUTFILE;
open INFILE, "<example";
lives_ok {
    $pars->read( \*INFILE );
    is_deeply( [ $pars->get_records() ],
        ['Simple text'], 'Read correct data in file' );
}
'Exercising the ability to read from file handles directly';
lives_ok { $pars->read( FileHandle->new( 'example', 'r' ) ); }
'No issues in reading from a FileHandle object of STDIN';
unlink 'example';

## Testing the reading from filehandles on STDOUT and STDIN
lives_ok { $pars->filehandle( \*STDOUT ); }
'Some systems can read from STDOUT. Your system is one of them.';
lives_ok { $pars->filehandle( \*STDIN ); } 'No issues in reading from STDIN';

throws_ok { $pars->read( { a => 'b' } ); }
'Moose::Exception::ValidationFailedForInlineTypeConstraint',
    'Invalid type of argument for read() method';

lives_ok { $pars->read( 't/' . $fname ); }
'reads the contents of a file without dying';
is( $pars->last_record,  $content, 'Last record is correct' );
is( $pars->lines_parsed, 1,        'Read only one line' );
is_deeply( [ $pars->get_records ], [$content], 'Got correct file content' );

my $add = "This record is added";
lives_ok { $pars->save_record(); } 'Add nothing';
is( $pars->last_record, undef, 'Last record is undef' );
lives_ok { $pars->save_record($add); } 'Add another record';
is( $pars->lines_parsed, 1,    'Still only 1 line parsed' );
is( $pars->last_record,  $add, 'Last added record' );
is_deeply(
    [ $pars->get_records ],
    [ $content, undef, $add ],
    'But will contain all elements including an undef'
);

is( $pars->pop_record,   $add,     'Popped a record' );
is( $pars->lines_parsed, 1,        'Still only 1 line parsed' );
is( $pars->last_record,  undef,    'There was an undef in between' );
is( $pars->pop_record,   undef,    'Now undef is removed' );
is( $pars->last_record,  $content, 'Now the last record is the one earlier' );
is_deeply( [ $pars->get_records ],
    [$content], 'Got correct content after pop' );

done_testing;
