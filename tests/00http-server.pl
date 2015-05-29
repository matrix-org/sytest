use Net::Async::HTTP::Server;
use JSON qw( decode_json encode_json );

multi_test "Environment closures for receiving HTTP pokes",
    provides => [qw(
        test_http_server_uri_base await_http_request
        respond_with_http_to respond_with_json_to
    )],

    do => sub {

        my $listen_host = "localhost";
        my $listen_port = 8003;

        # Hash from path to the response to return for that path.
        my $responses = {};
        my $default_response = HTTP::Response->new( 200 );
        $default_response->add_content( "{}" );
        $default_response->content_type( "application/json" );
        $default_response->content_length( length $default_response->content );

        # Hashes from paths to arrays of pending requests and futures.
        my $pending_requests = {};
        my $pending_futures = {};

        my $handle_request = sub {
            my ( $request, $future ) = @_;
            my $method = $request->method;
            my $path = $request->path;
            my $content = $request->body;
            if ( $request->header( "Content-type" ) eq "application/json" ) {
                $content = decode_json $content;
            }
            $future->done($content, $request);
        };

        my $respond_with_http_to = sub {
            my ( $path, $response ) = @_;
            $responses->{$path} = $response;
        };

        provide respond_with_http_to => $respond_with_http_to;

        my $respond_with_json_to = sub {
            my ( $path, $response_json ) = @_;
            my $content = encode_json $response_json;
            my $response = HTTP::Response->new( 200 );
            $response->add_content( $content );
            $response->content_type( "application/json" );
            $response->content_length( length $content );
            $respond_with_http_to->($path, $response);
        };

        provide respond_with_json_to => $respond_with_json_to;

        my $http_server = Net::Async::HTTP::Server->new(
            on_request => sub {
                my ( $self, $request ) = @_;
                my $method = $request->method;
                my $path = $request->path;

                $request->respond( $responses->{$path} // $default_response );
                if ( $CLIENT_LOG ) {
                    print STDERR "\e[1;32mReceived Request\e[m for $method $path:\n";
                    #TODO log the HTTP Request headers
                    print STDERR "  $_\n" for split m/\n/, $request->body;
                    print STDERR "-- \n";
                }
                my $pending_future = shift @{$pending_futures->{$path}};
                if (defined $pending_future) {
                    $handle_request->($request, $pending_future);
                } else {
                    push @{$pending_requests->{$path}}, $request;
                }
            }
        );

        my $uri_base = "http://$listen_host:$listen_port";

        provide test_http_server_uri_base => $uri_base;

        my $await_http_request;
        $await_http_request = sub {
            my ($path, $matches) = @_;

            my $future = $loop->new_future();
            my $pending_request = shift @{$pending_requests->{$path}};
            if (defined $pending_request) {
                $handle_request->($pending_request, $future);
            } else {
                push @{$pending_futures->{$path}}, $future;
            }
            return $future->then(sub {
                my ($body, $request) = @_;
                if ($matches->($body, $request)) {
                    return Future->done($body, $request);
                } else {
                    return $await_http_request->($path, $matches);
                }
            });
        };

        provide await_http_request => $await_http_request;

        $loop->add( $http_server );
        my $http_client = SyTest::HTTPClient->new(uri_base => $uri_base);
        $loop->add($http_client);

        $http_server->listen(
            addr => {
                family => "inet",
                socktype => "stream",
                port => $listen_port
            },
        )->then( sub {
            pass "Listening on $uri_base";
            $http_client->do_request_json(
                method => "POST",
                uri     => "/http_server_self_test",
                content => {
                    "some_key" => "some_value",
                },
            );
        })->then( sub {
            Future->wait_any(
                $await_http_request->("/http_server_self_test", sub {1}),
                delay( 10 )->then_fail( "Timed out waiting for request" ),
            );
        })->then( sub {
            my ( $body ) = @_;
            unless ($body->{some_key} eq "some_value") {
                die "Expected JSON with {\"some_key\":\"some_value\"}";
            }
            $respond_with_json_to->("/http_server_self_test" => {
                "response_key" => "response_value",
            });
            $http_client->do_request_json(
                method => "POST",
                uri     => "/http_server_self_test",
                content => {},
            );
        })->then( sub {
            my ( $body ) = @_;
            unless ($body->{response_key} eq "response_value") {
                die "Expected JSON with {\"response_key\":\"response_value\"}";
            }
            pass "HTTP server self-checks pass";
            Future->done(1);
        });
    }
