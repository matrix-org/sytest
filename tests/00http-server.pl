use Net::Async::HTTP::Server;

multi_test "Environment closures for receiving HTTP pokes",
    provides => [qw( test_http_server_address await_http_request )],

    do => sub {
        my $pending_requests = [];
        my $pending_futures = [];
        my $response = HTTP::Response->new( 200 );
        $response->add_content( "{}" );
        $response->content_type( "application/json" );
        $response->content_length( length $response->content );

        my $httpserver = Net::Async::HTTP::Server->new(
            on_request => sub {
                my ( $self, $req ) = @_;
                $req->respond( $response );
                if (scalar @$pending_futures) {
                    my $pending_future = shift $pending_futures;
                    $pending_future->done($req);
                } else {
                    push $pending_requests, $req;
                }
            }
        );

        provide test_http_server_address => "http://localhost:8003";

        provide await_http_request => sub {
            if (scalar @$pending_requests) {
                my $req = shift $pending_requests;
                return Future->done($req);
            } else {
                my $future = $loop->new_future();
                push $pending_futures, $future;
                return $future;
            }
        };

        $loop->add( $httpserver );

        $httpserver->listen(
            addr => { family => "inet", socktype => "stream", port => 8003},
        )->then( sub {
            pass "Listening on http://localhost:8003";
            Future->done(1);
        });
    }

