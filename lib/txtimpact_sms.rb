require 'net/http'
require 'uri'

username = 'Rubygems'
password = 'Rubygems'
profile_id = 2
short_code = 27126
vasid = '1334'
test_number = '610423368953'

# TODO parse results and raise exceptions based on output
class TxtImpact

  # Initializes a TxtImpact object with the common profile info needed
  # for making connections.
  # @param [Hash] opts The profile connection options
  # @option opts [String] :username The user name to connect as
  # @option opts [String] :password The password (in plain text) for connecting
  # @option opts [Integer] :profile_id The id of the profile
  # @options opts [Integer] :short_code The short code for the account
  # @options opts [Integer] :vasid The vasid of the account
  def initialize(opts)
    valid_keys =[:username, :password, :profile_id, :short_code, :vasid]
    if opts.keys.sort != valid_keys.sort
      puts opts.keys
      raise ArgumentError.new "The options must only have the keys #{valid_keys}"
    end

    opts.each do |key, value|
      instance_variable_set("@#{key}", value)
    end

  end

  attr_reader :username, :password, :vasid, :profile_id, :short_code

  alias :userid :username

  public
  # sends an sms
  # @param [Integer] to_number DESTINATION MOBILE NUMBER. [(country
  #   code) + mobile number] e.g 17321234567 (for
  #   US), 919810601000 (for India)
  # @param text The message text
  def send_sms(to_number, text)
    url = URI.parse('http://smsapi.wire2air.com/smsadmin/submitsm.aspx')
    Net::HTTP.post_form(url, {
      'VERSION' => '2.0',
      'USERID' => username,
      'PASSWORD' => password,
      'VASID' => vasid,
      'PROFILEID' => profile_id,
      'FROM' => short_code,
      'TO' => to_number,
      'TEXT' => text,
      # TODO 'DeliveryDateTime' => ''
    })

  end

  def subscribe_credits(keyword_credits = 1)
    url = URI.parse('http://mzone.wire2air.com/mserver/api/subscribekeywords.aspx')
    Net::HTTP.post_form(url, {
        'USERID' => userid,
        'PASSWORD' => password,
        'KEYWORDREDITS' => keyword_credits

    })

  end


end


