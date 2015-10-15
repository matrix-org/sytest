my $content = <<'EOF';
Here is the content I am uploading
EOF

my $content_type = "text/plain";
my $content_id;

test "POST /media/v1/upload can create an upload",
   requires => [qw( first_api_client ), local_user_preparer() ],

   provides => [qw( can_upload_media )],

   do => sub {
      my ( $http, $user ) = @_;

      # Because we're POST'ing non-JSON
      $http->do_request(
         method   => "POST",
         full_uri => "/_matrix/media/v1/upload",
         params => {
            access_token => $user->access_token,
         },

         content_type => $content_type,
         content      => $content,
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( content_uri ));

         provide can_upload_media => 1;

         my $content_uri = URI->new( $body->{content_uri} );
         $content_id = [ $content_uri->authority, $content_uri->path ];

         Future->done(1);
      });
   };

test "GET /media/v1/download can fetch the value again",
   requires => [qw( first_api_client
                    can_upload_media )],

   provides => [qw( can_download_media )],

   check => sub {
      my ( $http ) = @_;

      $http->do_request(
         method   => "GET",
         full_uri => "/_matrix/media/v1/download/" . join( "", @$content_id ),
         # No access_token; it should be public
      )->then( sub {
         my ( $got_content, $response ) = @_;

         $got_content eq $content or
            die "Content not as expected";
         $response->content_type eq $content_type or
            die "Content-Type not as expected";

         provide can_download_media => 1;

         Future->done(1);
      });
   };
