use URI::Escape qw( uri_escape );

my $FILENAME = "\xf0\x9f\x90\x94";
my $FILENAME_ENCODED = uc uri_escape( $FILENAME );

my $content_id;

our $API_CLIENTS;

test "Can upload with Unicode file name",
   requires => [ $API_CLIENTS, local_user_fixture(),
                 qw( can_upload_media )],

   provides => [qw( can_upload_media_unicode )],

   do => sub {
      my ( $clients, $user ) = @_;
      my $http = $clients->[0];

      $http->do_request(
         method       => "POST",
         full_uri     => "/_matrix/media/v1/upload",
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
         provide can_upload_media_unicode => 1;

         Future->done(1)
      });
   };

# These next two tests do the same thing with two different HTTP clients, to
# test locally and via federation

sub test_using_client
{
   my ( $client ) = @_;

   $client->do_request(
      method   => "GET",
      full_uri => "/_matrix/media/v1/download/$content_id",
   )->then( sub {
      my ( $body, $response ) = @_;

      my $disposition = $response->header( "Content-Disposition" );
      uc $disposition eq uc "inline; filename*=utf-8''$FILENAME_ENCODED" or
         die "Expected a UTF-8 filename parameter";

      Future->done(1);
   });
}

test "Can download with Unicode file name locally",
   requires => [ $API_CLIENTS,
                 qw( can_upload_media_unicode )],

   check => sub {
      my ( $clients ) = @_;
      test_using_client( $clients->[0] );
   };

test "Can download with Unicode file name over federation",
   requires => [ $API_CLIENTS,
                 qw( can_upload_media_unicode ) ],

   check => sub {
      my ( $clients ) = @_;
      test_using_client( $clients->[1] );
   };

test "Can download specifying a different Unicode file name",
   requires => [ $API_CLIENTS,
                 qw( can_upload_media_unicode )],

   check => sub {
      my ( $clients ) = @_;
      my $http = $clients->[0];

      my $alt_filename_encoded = "%E2%98%95";

      $http->do_request(
         method   => "GET",
         full_uri => "/_matrix/media/v1/download/$content_id/$alt_filename_encoded",
      )->then( sub {
         my ( $body, $response ) = @_;

         my $disposition = $response->header( "Content-Disposition" );
         uc $disposition eq uc "inline; filename*=utf-8''$alt_filename_encoded" or
            die "Expected a UTF-8 filename parameter";

         Future->done(1);
      });
   };
