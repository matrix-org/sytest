use HTTP::Headers::Util qw( split_header_words );
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


=head2 upload_test_content

   my ( $content_id, $content_uri ) = upload_test_content(
      $user, filename => "filename",
   ) -> get;

Uploads some test content with the given filename.

Returns the content id of the uploaded content.

=cut
sub upload_test_content
{
   my ( $user, %params ) = @_;

   $user->http->do_request(
      method       => "POST",
      full_uri     => "/_matrix/media/r0/upload",
      content      => "Test media file",
      content_type => "text/plain",

      params => {
         access_token => $user->access_token,
         %params,
      },
   )->then( sub {
      my ( $body ) = @_;

      assert_json_keys( $body, qw( content_uri ));

      my $content_uri = $body->{content_uri};

      my $parsed_uri = URI->new( $body->{content_uri} );
      my $server = $parsed_uri->authority;
      my $path = $parsed_uri->path;

      my $content_id = "$server$path";

      Future->done( $content_id, $content_uri );
   });
}
push our @EXPORT, qw( upload_test_content );


=head2 get_media

   my ( $content_disposition_params, $content ) = get_media( $http, $content_id ) -> get;

Fetches a piece of media from the server.

=cut
sub get_media
{
   my ( $http, $content_id ) = @_;

   $http->do_request(
      method   => "GET",
      full_uri => "/_matrix/media/r0/download/$content_id",
   )->then( sub {
      my ( $body, $response ) = @_;

      my $disposition = $response->header( "Content-Disposition" );

      my $cd_params;
      if ( defined $disposition ) {
         $cd_params = parse_content_disposition_params( $disposition );
      }
      Future->done( $cd_params, $body );
   });
}
push @EXPORT, qw( get_media );

sub parse_content_disposition_params {
   my ( $disposition ) = @_;
   my @parts = split_header_words( $disposition );

   # should be only one list of words
   assert_eq( scalar @parts, 1, "number of content-dispostion header lists" );
   @parts = @{$parts[0]};

   # the first part must be 'inline'
   my $k = shift @parts;
   my $v = shift @parts;
   assert_eq( $k, "inline", "content-disposition" );
   die "invalid CD" if defined $v;

   my %params;
   while (@parts) {
      my $k = shift @parts;
      my $v = shift @parts;
      die "multiple $k params" if exists $params{$k};
      die "unknown param $k" unless ( $k eq 'filename' || $k eq 'filename*' );
      $params{$k} = $v;
   }
   return \%params;
}


test "Can upload with Unicode file name",
   requires => [ local_user_fixture(),
                 qw( can_upload_media )],

   proves => [qw( can_upload_media_unicode )],

   do => sub {
      my ( $user ) = @_;

      upload_test_content( $user, filename=>$FILENAME )->then( sub {
         ( $content_id ) = @_;
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

   get_media( $client, $content )->then( sub {
      my ( $cd_params ) = @_;

      if (exists( $cd_params->{'filename'} )) {
         assert_eq( $cd_params->{'filename'}, "utf-8\"$FILENAME\"", "filename" );
      } else {
         assert_eq( $cd_params->{'filename*'}, "utf-8''$FILENAME_ENCODED", "filename*" );
      }

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

      my $alt_filename = "☕";
      my $alt_filename_encoded = "%E2%98%95";

      $http->do_request(
         method   => "GET",
         full_uri => "/_matrix/media/r0/download/$content_id/$alt_filename_encoded",
      )->then( sub {
         my ( $body, $response ) = @_;

         my $disposition = $response->header( "Content-Disposition" );
         uc $disposition eq uc "inline; filename*=utf-8''$alt_filename_encoded" or
            uc $disposition eq uc "inline; filename=utf-8\"$alt_filename\"" or
            die "Expected a UTF-8 filename parameter";

         Future->done(1);
      });
   };
