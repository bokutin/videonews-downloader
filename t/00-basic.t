use Test::More;

use Modern::Perl;

#use Carp::REPL qw(nodie repl);
use Data::Dumper;
use File::Temp;
use URI;
use URI::QueryParam;

use_ok("App::videonewsdownloader::Container", "container");
use_ok("App::videonewsdownloader");

my $new_instance = sub {
    my $config = container("config");
    my $www = App::videonewsdownloader->new(
        username => $config->get->{username},
        password => $config->get->{password},
    );
};

my $www = $new_instance->();

subtest login => sub {
    ok( !$www->is_logged_in );
    ok( $www->login );
    ok(  $www->is_logged_in );

    done_testing;
};

$www = $new_instance->();

my $page_uri;

subtest pages => sub {
    my @page_uris = $www->all_page_uris;
    ok( @page_uris );

    $page_uri = $page_uris[0];

    done_testing;
};

my $wmv_link;

subtest wmv_links => sub {
    plan skip_all => "page not found." unless $page_uri;

    my @wmv_links = $www->wmv_links( uri => $page_uri );
    ok( @wmv_links );

    $wmv_link = $wmv_links[0];

    done_testing;
};

subtest mms_uri => sub {
    plan skip_all => "wmv link not found." unless $wmv_link;

    my $http_uri = $wmv_link;
    my $mms_uri  = $www->mms_uri_by_http_uri($http_uri);

    ok($http_uri);
    ok($mms_uri);

    done_testing;
};

subtest download_wmv => sub {
    plan skip_all => "wmv link not found." unless $wmv_link;

    my $tmp = File::Temp->new(SUFFIX => '.wmv');
    my $ret = $www->download_wmv( http_uri => $wmv_link, file => $tmp->filename, mock => 1 );

    ok($ret);

    done_testing;
};

done_testing;