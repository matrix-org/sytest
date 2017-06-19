use File::Basename qw( dirname );
use File::Slurper qw( read_binary );

my $dir = dirname __FILE__;

multi_test "POSTed media can be thumbnailed",
   requires => [ local_admin_fixture(), local_user_and_room_fixtures(), remote_user_fixture(),
                 qw( can_upload_media can_download_media )],

   do => sub {
      my ( $admin, $user, $room_id, $remote_user ) = @_;

      my $pngdata = read_binary( "$dir/test.png" );

      my $content_id;

      # Because we're POST'ing non-JSON
      $user->http->do_request(
         method => "POST",
         full_uri => "/_matrix/media/r0/upload",
         params => {
            access_token => $user->access_token,
         },

         content_type => "image/png",
         content      => $pngdata,
      )->then( sub {
         my ( $body ) = @_;

         my $content_uri = URI->new( $body->{content_uri} );

         my $server = $content_uri->authority;
         my $path = $content_uri->path;

         $content_id = "$server$path";

         matrix_send_room_message( $user, $room_id,
            content => { msgtype => "m.image", body => "test.png", url => $content_uri }
         );
      })->then( sub {
         do_request_json_for( $admin,
            method  => "POST",
            uri     => "/r0/admin/quarantine_media/$room_id",
            content => {}
         )
      })->SyTest::pass_on_done( "Quarantine returns success" )
      ->then( sub {
         $user->http->do_request(
            method   => "GET",
            full_uri => "/_matrix/media/r0/download/$content_id",
         )->main::expect_http_404
      })->SyTest::pass_on_done( "404 on getting quarantined local media" )
      ->then( sub {
         $user->http->do_request(
            method => "GET",
            full_uri => "/_matrix/media/r0/thumbnail/$content_id",
            params => {
               width  => 32,
               height => 32,
               method => "scale",
            }
         )->main::expect_http_404
      })->SyTest::pass_on_done( "404 on getting quarantined local thumbnails" )
      ->then( sub {
         $remote_user->http->do_request(
            method   => "GET",
            full_uri => "/_matrix/media/r0/download/$content_id",
         )->main::expect_http_404
      })->SyTest::pass_on_done( "404 on getting quarantined remote media" )
      ->then( sub {
         $remote_user->http->do_request(
            method => "GET",
            full_uri => "/_matrix/media/r0/thumbnail/$content_id",
            params => {
               width  => 32,
               height => 32,
               method => "scale",
            }
         )->main::expect_http_404
      })->SyTest::pass_on_done( "404 on getting quarantined remote thumbnails" );
   };
