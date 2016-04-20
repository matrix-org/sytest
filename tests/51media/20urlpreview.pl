use File::Basename qw( dirname );
use File::Slurper qw( read_binary );

my $OGRAPH_TITLE = "The Rock";
my $OGRAPH_TYPE = "video.movie";
my $OGRAPH_URL = "http://www.imdb.com/title/tt0117500/";
my $OGRAPH_IMAGE = "test.png";

my $EXAMPLE_OPENGRAPH_HTML = <<"EOHTML";
<html prefix="og: http://ogp.me/ns#">
<head>
<title>The Rock (1996)</title>
<meta property="og:title" content="$OGRAPH_TITLE" />
<meta property="og:type" content="$OGRAPH_TYPE" />
<meta property="og:url" content="$OGRAPH_URL" />
<meta property="og:image" content="$OGRAPH_IMAGE" />
</head>
<body></body>
</html>

EOHTML

my $DIR = dirname __FILE__;

multi_test "Test that a message is pushed",
   requires => [
      local_user_fixture( with_events => 0 ), $main::TEST_SERVER_INFO,
   ],

   do => sub {
      my ( $user, $test_server_info ) = @_;

      Future->needs_all(
         # TODO(check that the HTTP poke is actually the poke we wanted)
         await_http_request( "/test.html", sub {
            return 1;
         })->then( sub {
            my ( $request ) = @_;

            my $response = HTTP::Response->new( 200 );
            $response->add_content( $EXAMPLE_OPENGRAPH_HTML );
            $response->content_type( "text/html" );
            $response->content_length( length $response->content );

            $request->respond( $response );

            Future->done( $request );
         })->SyTest::pass_on_done( "URL was fetched" ),

         await_http_request( "/test.png", sub {
            return 1;
         })->then( sub {
            my ( $request ) = @_;

            my $pngdata = read_binary( "$DIR/test.png" );

            my $response = HTTP::Response->new( 200 );
            $response->add_content( $pngdata );
            $response->content_type( "image/png" );
            $response->content_length( length $response->content );

            $request->respond( $response );

            Future->done( $request );
         })->SyTest::pass_on_done( "Image was fetched" ),

         $user->http->do_request(
            method   => "GET",
            full_uri => "/_matrix/media/r0/preview_url",
            params   => {
               url          => $test_server_info->client_location . "/test.html",
               access_token => $user->access_token,
            },
         ),
      )->SyTest::pass_on_done( "Preview returned successfully" )
      ->then( sub {
         my ( undef, undef, $preview_body ) = @_;

         log_if_fail "Preview body", $preview_body;

         assert_json_keys( $preview_body, qw( og:title og:type og:url og:image matrix:image:size og:image:height og:image:width ) );

         assert_eq( $preview_body->{"og:title"}, $OGRAPH_TITLE );
         assert_eq( $preview_body->{"og:type"}, $OGRAPH_TYPE );
         assert_eq( $preview_body->{"og:url"}, $OGRAPH_URL );
         assert_eq( $preview_body->{"matrix:image:size"}, 2239 );
         assert_eq( $preview_body->{"og:image:height"}, 129 );
         assert_eq( $preview_body->{"og:image:width"}, 279 );

         $preview_body->{"og:image"} =~ m/^mxc:\/\// or die "Expected mxc url for og:image";

         Future->done( 1 );
      })->SyTest::pass_on_done( "Preview API returned expected values" )
   };
