require 'optparse'
require 'json'
require 'open-uri'
require 'cgi'
require 'colorize'

Options = Struct.new(:name, :username, :password)

class Parser
  def self.parse(options)
    args = Options.new("parser")

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: searchcode.rb [options]"

      opts.on("-nOrgName", "--name=Org Name", "IMPORTANT: Organization's name as seen on GitHub") do |n|
        args.name = n
      end
      
      opts.on("-uUsername", "--username=GitHub Username", "GitHub Username") do |u|
        args.username = u
      end
      
      opts.on("-pPassword", "--password=GitHub Password", "GitHub Password") do |p|
        args.password = p
      end

      opts.on("-h", "--help", "Prints available options") do
        puts opts
        exit
      end
    end

    opt_parser.parse!(options)
    return args
  end
end

class PrintTable
  
  attr_reader :hash, :length_info
  
  def initialize(hash={})
    @hash = hash
    @length_info = get_length_values
    make_titles
    print_user_details
  end
  
  def get_length_values
    key_lengths = []
    val_lengths = []
    hash.each do |key, value|
      key_lengths << key.to_s.length
      val_lengths << value.to_s.length
    end
    { :key_length => key_lengths.sort_by(&:to_i).last, 
      :value_length => val_lengths.sort_by(&:to_i).last
    }
  end
  
  def make_titles
    title = ''
    title << "User" + ' ' * length_info[:key_length]
    title << "Details" + ' ' * length_info[:value_length]
    title << "\n" + '=' * 4
    title << " " * (length_info[:key_length])
    title << '=' * 7 + "\n\n"
    puts title
  end
  
  def print_user_details
    detail = ""
    hash.each do |key, value| 
      detail << key + ' ' * (length_info[:key_length] - key.length + 4)
      detail << value.to_s
      detail << "\n"
    end
    detail << "\n"
    puts detail
  end
  
end

class GetOrgMembers
  
  attr_reader :name, :repos_list, :username, :password
  
  def initialize(options=Struct.new)
    @name = options.name
    @username = options.username
    @password = options.password 
    @repos_list = []
  end
  
  def fetch
    @members = JSON.parse(open("https://api.github.com/orgs/#{name}/members", http_basic_authentication: [username, password] ).read)
  rescue OpenURI::HTTPError => e
    case e.to_s
    when "403 Forbidden"
      puts "Receiving a 403 so it is likely API restrictions, gonna need github creds (see help)"
    when "404 Not Found"
      puts "Receiving a 404 so.....Does that org exist? (double check the name)"
    else  
      puts e
    end
    exit
  end
  
  def retrieve_member_repo_list(member)
    repos_url = member['repos_url']
    begin
      repo_info = JSON.parse(open(repos_url, http_basic_authentication: [username, password]).read)
    rescue OpenURI::HTTPError => e
      puts "returned #{e} for the following repo url: #{repos_url}"
      return
    end
    repo_info.each do | repo| 
      repos_list << repo['clone_url']
      repos_list << repo['git_url']
      repos_list << repo['ssh_url']
      repos_list << repo['svn_url']
    end 
  end 
  
  
  def print_relevant_details
    if @members.nil?
     puts "No members Returned, Sorry"
     exit
    end
    @members.each do |member|
      PrintTable.new(member)
      retrieve_member_repo_list(member)
    end
  end

end

class SearchEngine
  
  attr_reader :list_of_search_results
  
  def initialize
    @list_of_search_results = {}
    run
  end
  
  def run
    collector
  end
  
  def collector
    keywords.each do |keyword|
      list = []
      keyword = CGI::escape(keyword)
      (0..49).each do |i|
        url = "https://searchcode.com/api/codesearch_I/?q=#{keyword}&p=#{i}&src=2&per_page=100"
        response = JSON.parse(open(url).read)
        break if response["results"].empty?
        list << response["results"].inject([]) do |arr, result|
          arr << result["repo"]
          arr
        end
      end
      list_of_search_results[keyword.to_sym] = list.flatten!
    end
  end
  
  def keywords
    [
      "api_token"
    ]
  end    
  
end

class FindMatch
  
  def initialize(search_result_list={}, member_repos=[])
    puts "No Results...thats strange" and exit if (search_result_list.empty? || member_repos.empty?)
    member_repos.each do |repo_url|
    match = search_result_list.inject([]) do |arr,(key,value)| 
      if value.include?(repo_url)
        arr << [key, repo_url]
      end
      arr.flatten
    end
    yay(match) if not match.empty?
    end
  end
  
  def yay(match=[])
    keyword, repo = match
    puts "[woot] Found this repo #{repo} which has a keyword of \'#{keyword}\'".green
  end

end


args = ARGV.empty? ? %w{--help} : ARGV
options = Parser.parse args
p options if args.include?('--help')

members = GetOrgMembers.new(options)
members.fetch
members.print_relevant_details
member_repos = members.repos_list
search = SearchEngine.new
matches = FindMatch.new(search.list_of_search_results, member_repos)


