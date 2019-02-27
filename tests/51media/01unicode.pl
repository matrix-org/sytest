use URI::Escape qw( uri_escape );
use SyTest::TCPProxy;

my $FILENAME = "\xf0\x9f\x90\x94";
my $FILENAME_ENCODED = uc uri_escape( $FILENAME );

my $content_id;

my $PROXY_SERVER = fixture(
   name => 'PROXY_SERVER',

   requires => [ $main::HOMESERVER_INFO[0] ],

   setup => sub {
      my ( $server_info ) = @_;

      $OUTPUT->diag( "Starting proxy server" );

      my $listener = SyTest::TCPProxy->new(
         host   => $server_info->federation_host,
         port   => $server_info->federation_port,
         output => $OUTPUT,
      );

      $loop->add( $listener );

      $listener->listen(
         addr => { family => "inet" },
      )->on_done( sub {
         my $sock = $listener->read_handle;
         $OUTPUT->diag( "Proxy now listening at port " . $sock->sockport );
         return $listener;
      });
   },

   teardown => sub {
      my ( $listener ) = @_;
      $listener->close();
   },
);


test "Can upload with Unicode file name",
   requires => [ $main::API_CLIENTS[0], local_user_fixture(),
                 qw( can_upload_media )],

   proves => [qw( can_upload_media_unicode )],

   do => sub {
      my ( $http, $user ) = @_;

      $http->do_request(
         method       => "POST",
         full_uri     => "/_matrix/media/r0/upload",
         content      => "Test media file",
         content_type => "text/plain",

         params => {
            access_token => $user->access_token,
            filename     => $FILENAME,
         }
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( content_uri ));

         my $content_uri = URI->new( $body->{content_uri} );
         my $server = $content_uri->authority;
         my $path = $content_uri->path;

         $content_id = "$server$path";

         Future->done(1)
      });
   };

# These next two tests do the same thing with two different HTTP clients, to
# test locally and via federation

sub test_using_client
{
   my ( $client, $content ) = @_;

   if( ! defined( $content )) {
       $content = $content_id;
   }

   $client->do_request(
      method   => "GET",
      full_uri => "/_matrix/media/r0/download/$content",
   )->then( sub {
      my ( $body, $response ) = @_;

      my $disposition = $response->header( "Content-Disposition" );
      uc $disposition eq uc "inline; filename*=utf-8''$FILENAME_ENCODED" or
         die "Expected a UTF-8 filename parameter";

      Future->done(1);
   });
}

test "Can download with Unicode file name locally",
   requires => [ $main::API_CLIENTS[0],
                 qw( can_upload_media_unicode )],

   check => sub {
      my ( $http ) = @_;
      test_using_client( $http );
   };

test "Can download with Unicode file name over federation",
   requires => [ $main::API_CLIENTS[1],
                 qw( can_upload_media_unicode ) ],

   check => sub {
      my ( $http ) = @_;
      test_using_client( $http );
   };

test "Alternative server names do not cause a routing loop",
   # https://github.com/matrix-org/synapse/issues/1991
   requires => [ $main::API_CLIENTS[0], $PROXY_SERVER ],

   check => sub {
      my ( $http, $proxy ) = @_;
      # we use a proxy server which routes connections straight back to the
      # homeserver, to mimic the behaviour when the remote server name points
      # back to the homeserver.
      my $sock = $proxy->read_handle;
      my $proxy_address = "localhost:" . $proxy->read_handle->sockport;
      my $content = "$proxy_address/test_content";
      test_using_client( $http, $content )->main::expect_http_404;
   };

test "Can download specifying a different Unicode file name",
   requires => [ $main::API_CLIENTS[0],
                 qw( can_upload_media_unicode )],

   check => sub {
      my ( $http ) = @_;

      my $alt_filename_encoded = "%E2%98%95";

      $http->do_request(
         method   => "GET",
         full_uri => "/_matrix/media/r0/download/$content_id/$alt_filename_encoded",
      )->then( sub {
         my ( $body, $response ) = @_;

         my $disposition = $response->header( "Content-Disposition" );
         uc $disposition eq uc "inline; filename*=utf-8''$alt_filename_encoded" or
            die "Expected a UTF-8 filename parameter";

         Future->done(1);
      });
   };
