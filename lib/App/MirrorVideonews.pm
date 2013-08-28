package App::MirrorVideonews;

use utf8;
use Modern::Perl;
use Moose;

use App::MirrorVideonews::Exceptions;
use App::MirrorVideonews::Page;
use File::Spec::Functions qw(catfile);
use HTTP::Request::Common qw(HEAD);
use List::BinarySearch qw(bsearch_custom);
use List::Util qw(first);
use POSIX qw(strftime);
use Safe::Isa;
use Time::Duration;
use WWW::Scripter;

has mech          => ( is => "rw", isa => "WWW::Scripter", lazy_build => 1 );
has is_logged_in  => ( is => "rw", isa => "Bool", default => 0 );
has username      => ( is => "ro", isa => "Str" );
has password      => ( is => "ro", isa => "Str" );
has save_dir      => ( is => "ro", isa => "Str" );
has archives_dirs => ( is => "ro", isa => "ArrayRef[Str]", default => sub { [] } );
has blob_types    => ( is => "ro", isa => "ArrayRef[Str]", default => sub { [qw(hls wmv wma)] } );

sub exists_file {
    my ($self, $basename) = @_;

    my @dirs = ($self->save_dir, @{$self->archives_dirs});
    first { -f } map { catfile($_, $basename) } @dirs;
}

sub login {
    my $self = shift;

    my $mech = $self->mech;

    die "Username required." unless $self->username;
    die "Password required." unless $self->password;

    $mech->get('http://www.videonews.com/');
    $mech->follow_link( url_regex => qr/ContentsRequestReceive\.jsp\?req=2\b/ );
    $mech->submit_form(
        with_fields => {
            memberName => $self->username,
            password   => $self->password,
        },
    );
    $mech->follow_link( url_regex => qr/javascript:doSubmit/ );

    my $text = $mech->document->documentElement->as_text;

    if ( $text =~ m/現在ログイン中です/ ) {
        $self->is_logged_in(1);
    }
    else {
        die "login failed.";
    }
}

sub marugeki_page_uris {
    my $self = shift;

    $self->_all_page_uris("http://www.videonews.com/charged/on-demand/index.php");
}

sub news_page_uris {
    my $self = shift;

    $self->_all_page_uris("http://www.videonews.com/charged/news-commentary/index.php");
}

sub run {
    my $self = shift;

    my $start_time = time;

    $self->login unless $self->is_logged_in;

    my @marugeki_uris = $self->marugeki_page_uris;
    my @news_uris     = $self->news_page_uris;
    my @page_uris     = (@marugeki_uris, @news_uris);
    say sprintf("%d pages found. (marugeki: %d, news: %d)", 0+@page_uris, 0+@marugeki_uris, 0+@news_uris);
    
    my @downloaded;
    my @not_found;
    my @all_blobs;
    my @skipped;
    my $mech = $self->mech;
    PAGE: for my $page_uri (@page_uris) {
        say "==> $page_uri";
        $mech->get($page_uri);
        my $page = App::MirrorVideonews::Page->new( app => $self );
        for my $type (@{$self->blob_types}) {
            for my $blob ($page->blobs(uc($type))) {
                my $basename = $blob->save_as_basename;
                say "--> $basename";
                push @all_blobs, $blob;
                if (my $fn = $self->exists_file($basename)) {
                    say "skipping. $fn";
                    push @skipped, $basename;
                }
                else {
                    eval { $blob->download( catfile($self->save_dir, $basename) ) };
                    if (my $err = $@) {
                        if ($err->$_isa("App::MirrorVideonews::Exception::NotFound")) {
                            push @not_found, $basename;
                        }
                        elsif ($err->$_isa("App::MirrorVideonews::Exception::TokenTimeout")) {
                            # HLSのURIのトークンキーらしきものが、タイムアウトしている場合
                            say "The token seems to be expired. @{[ $blob->uri ]}";
                            say "Retry fetching page. @{[ $page_uri ]}";
                            redo PAGE;
                        }
                        else {
                            die $err;
                        }
                    }
                    else {
                        push @downloaded, $basename;
                    }
                }
            }
        }
    }

    my $finish_time = time;

    say "";
    say "";
    say sprintf("%d pages, %d blobs, %d skipped, %d downloaded, %d not found", 0+@page_uris, 0+@all_blobs, 0+@skipped, 0+@downloaded, 0+@not_found);
    say "start: " . strftime("%Y-%m-%d %H:%M:%S", localtime($start_time));
    say "finish: " . strftime("%Y-%m-%d %H:%M:%S", localtime($finish_time));
    say "elapsed: " . duration($finish_time - $start_time);
    say "not found: ";
    say "\t$_" for @not_found;
    say "succeeded.";

    exit 0;
}

our @HAYSTACK = (1..100);
sub _all_page_uris {
    my ($self, $index) = @_;

    my $mech           = $self->mech;
    my $needle         = [$self, $index];
    my $first_found_ix = bsearch_custom \&_comparator, $needle, @HAYSTACK;

    unless (defined $first_found_ix) {
        @HAYSTACK = (1 .. @HAYSTACK*2);
        goto \&_all_page_uris;
    }

    map { _uri_with_page_num($index, $_) } (1 .. $first_found_ix);
}

sub _build_mech {
    my $self = shift;

    my $mech = WWW::Scripter->new(
        agent => 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)',
    );
    $mech->use_plugin('JavaScript');

    # warnを抑制
    #
    # TypeError: undefined has no properties, not even one named expando at https://ajax.googleapis.com/ajax/libs/jquery/1/jquery.min.js, line 3.
    # Argument "\x{b}1" isn't numeric in addition (+) at /Users/bokutin/perl5/perlbrew/perls/perl-5.16.2/lib/site_perl/5.16.2/JE/Number.pm line 93.
    # TypeError: The object's 'attachEvent' property (undefined) is not a function at http://hlsp01.videonews.com/swf/js/swfobject.min.js, line 4.
    # ReferenceError: The variable JSON has not been declared at http://hlsp01.videonews.com/flash/?U2FsdGVkX1%2FW9CJDT71UvJ7YZKmH3tsdAklpgfFfWy0%3D, line 81.
    $mech->quiet(1);

    $mech;
}

sub _comparator {
    my ($needle, $haystack_item) = @_;

    my ($self, $index) = @$needle;
    my $page = $haystack_item;
    my $mech = $self->mech;
    my $uri  = _uri_with_page_num($index, $page);
    my $res  = $mech->simple_request( HEAD $uri );
    #warn "$page " . $res->code;
    $res->code == 200 ? 1 : 0;
}

sub _uri_with_page_num {
    my ($uri, $page) = @_;
    $uri =~ s/\.php/@{[ $page == 1 ? "" : "_$page" ]}.php/r;
}

__PACKAGE__->meta->make_immutable; no Moose; 1;