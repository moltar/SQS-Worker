# ABSTRACT: manages workers reading from an SQS queue
package SQS::Worker;
use Paws;
use Moose::Role;
use Data::Dumper;
use SQS::Consumers::Default;
use SQS::Consumers::DeleteAlways;

our $VERSION = '0.04';

requires 'process_message';

has queue_url => (is => 'ro', isa => 'Str', required => 1);
has region => (is => 'ro', isa => 'Str', required => 1);

has sqs => (is => 'ro', isa => 'Paws::SQS', lazy => 1, default => sub {
    my $self = shift;
    Paws->service('SQS', region => $self->region);
});

has log => (is => 'ro', required => 1);

has on_failure => (is => 'ro', isa => 'CodeRef', default => sub {
    return sub {
        my ($self, $message) = @_;
        $self->log->error("Error processing message " . $message->ReceiptHandle);
        $self->log->debug("Message Dump " . Dumper($message));
    }
});

has processor => (is => 'ro', lazy => 1, default => sub {
    my $self = shift;
    return SQS::Consumers::Default->new;
});

sub fetch_message {
    my $self = shift;
    $self->processor->fetch_message($self);
}

sub run {
    my $self = shift;
    while (1) {
        $self->fetch_message;
    }
}

sub delete_message {
    my ($self, $message) = @_;
    $self->sqs->DeleteMessage(
        QueueUrl      => $self->queue_url,
        ReceiptHandle => $message->ReceiptHandle,
    );
}

sub receive_message {
    my $self = shift;
    my $message_pack = $self->sqs->ReceiveMessage(
        WaitTimeSeconds => 20,
        QueueUrl => $self->queue_url,
        MaxNumberOfMessages => 1
    );
    return $message_pack;
}

1;

=head1 NAME

SQS::Worker

=head1 DESCRIPTION

This role is to be composed into the end user code that want to receive 
messages from an SQS queue. 

The worker is running uninterrumped, fetching messages from it's configured 
queue, one at a time and then executing the process_message of the consuming class.

The worker consumer can compose further funcionality by consuming more roles from the SQS::Worker namespace.

=head1 USAGE

Simple usage

	package MyConsumer;

	use Moose;
	with 'SQS::Worker';

	sub process_message {
		my ($self,$message) = @_;

    # $message is a Paws::SQS::Message
		# do something with the message 
	}

Composing automatic json decoding to perl data structure

	package MyConsumer;
  use Moose;
	with 'SQS::Worker', 'SQS::Worker::DecodeJson';

	sub process_mesage {
		my ($self, $data) = @_;
		
		# Do something with the data, already parsed into a structure
		my $name = $data->{name};

    # You get a logger attached to the worker so you can log stuff
    $c->log->info("I processed a message for $name");
	}

=head1 Bundled roles

L<SQS::Worker::DecodeJson> decodes the message body in json format and passes 

L<SQS::Worker::DecodeStorable> decodes the message body in Perl storable format

L<SQS::Worker::Multiplex> dispatches to different methods via a dispatch table

L<SQS::Worker::SNS> decodes a message sent from SNS and inflates it to a C<SNS::Notfication>

=head1 Creating your own processing module

Create a Moose role that wraps functionality around the method C<process_message>

  package PrefixTheMessage;
    use Moose::Role;

    around process_message => sub {
      my ($orig, $self, $message) = @_;
      return 'prefixed ' . $message->Body;
    };

  1;

And then use it inside your consumers

  package MyConsumer;
  
	use Moose;
	with 'SQS::Worker', 'SQS::Worker::DecodeJson';
  
	sub process_mesage {
		my ($self, $message) = @_;
    # surprise! $message is prefixed!
  }
  
  1;

=head1 Error handling

Any exception thrown from process_message will be treated as a failed message. Different
message processors treat failed messages in different ways

=head1 Message processors

L<SQS::Consumers::Default> Messages processed before deleting them from the queue. If a message fails, 
it will be treated by SQS as an unprocessed message, and will reappear in the queue to be processed
again by SQS (or delivered to a dead letter queue after N redeliveries if your SQS queue is configured 
appropiately

L<SQS::Consumers::DeleteAlways> Message deleted, then processed. If a message fails it will
not be reprocessed ever

=head1 SEE ALSO
 
L<Paws>
 
=head1 COPYRIGHT and LICENSE
 
Copyright (c) 2016 by CAPSiDE
 
This code is distributed under the Apache 2 License. The full text of the license can be found in the LICENSE file included with this module.
 
=head1 AUTHORS

Jose Luis Martinez, Albert Hilazo, Pau Cervera and Loic Prieto

=cut
