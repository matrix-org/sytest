test "Can upload with unicode file name",
   requires => [qw( first_v1_client user )],

   provides => [qw( unicode_content_id )],

   do => sub {
      my ( $http, $user ) = @_;

      $http->do_request(
         method       => "POST",
         full_uri     => "/_matrix/media/v1/upload",
         content      => "Test media file",
         content_type => "text/plain",

         params => {
            access_token => $user->access_token,
            filename     => "\xf0\x9f\x90\x94",
         }
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( content_uri ));

         my $content_uri = URI->new( $body->{content_uri} );
         my $server = $content_uri->authority;
         my $path = $content_uri->path;

         provide unicode_content_id => "$server$path";

         Future->done(1)
      });
   };

test "Can download with unicode file name",
   requires => [qw( first_v1_client unicode_content_id )],

   check => sub {
      my ( $http, $content_id ) = @_;

      $http->do_request(
         method   => "GET",
         full_uri => "/_matrix/media/v1/download/$content_id",
      )->then( sub {
         my ( $body, $response ) = @_;

         my $disposition = $response->header( "Content-Disposition" );
         $disposition eq "inline; filename*=utf-8''%F0%9F%90%94" or
            die "Expected a UTF-8 filename parameter";

         Future->done(1);
      });
   };

test "Can download specifying a unicode file name",
   requires => [qw( first_v1_client unicode_content_id )],

   check => sub {
      my ( $http, $content_id ) = @_;

      $http->do_request(
         method   => "GET",
         full_uri => "/_matrix/media/v1/download/$content_id/%E2%98%95",
      )->then( sub {
         my ( $body, $response ) = @_;

         my $disposition = $response->header( "Content-Disposition" );
         $disposition eq "inline; filename*=utf-8''%E2%98%95" or
            die "Expected a UTF-8 filename parameter";

         Future->done(1);
      });
   };

test "Can download with unicode file name over federation",
   requires => [qw( v1_clients unicode_content_id )],

   check => sub {
      my ( $clients, $content_id ) = @_;

      $clients->[1]->do_request(
         method   => "GET",
         full_uri => "/_matrix/media/v1/download/$content_id",
      )->then( sub {
         my ( $body, $response ) = @_;

         my $disposition = $response->header( "Content-Disposition" );
         $disposition eq "inline; filename*=utf-8''%F0%9F%90%94" or
            die "Expected a UTF-8 filename parameter: $disposition";

         Future->done(1);
      });
   }
