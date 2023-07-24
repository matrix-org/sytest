my $content_id;

# This test ensures an uploaded file may optionally be rendered inline
# in the browser. This is checked in get_media

sub test_using_client
{
   my ( $client ) = @_;
}

test "Can download a file that optionally inlines",
   requires => [ $main::API_CLIENTS[0] ],

   check => sub {
      my ( $http ) = @_;
      upload_test_content( $user, {} , "text/plain")->then( sub {
         ( $content_id ) = @_;
         get_media( $http, $content_id, 1 )->then( sub {
            Future->done(1);
         })
      });
   };
