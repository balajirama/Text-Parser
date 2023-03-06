
use strict;
use warnings;

use Test::More;
use Test::Exception;
use English;

BEGIN {
    use_ok 'Text::Parser';
}

my $fname = 't/random-data-from-internet.csv';

my $parser = Text::Parser->new( FS => qr/[,]/ );

$parser->add_rule(
    if => '$NR',
    do =>
        'my $i = 0; my %rec = map { ($_ => $this->field($i++)) } @{~header}; return \%rec;',
);
$parser->add_rule(
    do          => '~header = [ @{1+} ];',
    dont_record => 1,
);

sub read_with_text_parser {
    $parser->read($fname);
}

use FileHandle;
use String::Util 'trim';

sub read_with_native_perl {
    my $fh = FileHandle->new();
    $fh->open($fname);
    my (@data) = ();
    my $header = undef;
    while (<$fh>) {
        chomp;
        $_ = trim($_);
        my (@field) = split /[,]/;
        next if not @field;
        if ($NR) {
            my $i   = 0;
            my %rec = map { $_ => $field[ $i++ ] } @{$header};
            push @data, \%rec;
        } else {
            $header = \@field;
        }
    }
    close $fh;
    return \@data;
}

read_with_text_parser();
my $data = read_with_native_perl();
is_deeply( [ $parser->get_records ], $data, 'Matching results' );

use Benchmark;

my $iter     = 10;
my $native_t = timeit( $iter, \&read_with_native_perl )->real;
my $t_parser = timeit( $iter, \&read_with_text_parser )->real;

ok( $native_t <= $t_parser,
    "t_parser ($t_parser s) >= native_t ($native_t s)" );
done_testing;
