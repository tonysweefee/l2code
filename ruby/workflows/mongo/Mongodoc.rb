require 'mongo'
include Mongo

class Mongodoc

	# class var defaults, settable via Mongodoc.configure
	@HOST='localhost'
	@PORT=27017
	@DB='mongodoc_test'
	@paging_anchor_hash=nil

	attr_accessor :raw_hash		# this is the raw hash going in and out of mongo

	#
	# class methods
	#
	class << self

		# set these via Mongodoc.configure
		attr_reader :PORT, :HOST, :DB

		def configure(options = {})
			@HOST = options[:host] || @HOST
			@PORT = options[:port] || @PORT
			@DB = options[:db] || @DB
		end

		def client(options = {}, &block)
			host=options[:host] || Mongodoc.HOST
			port=options[:port] || Mongodoc.PORT

			client=MongoClient.new(host,port)

			return client unless block
			begin
				block.call(client)
			ensure
				client.close
			end
		end

		def db(options = {}, &block)
			db_host=options[:host] || Mongodoc.HOST
			db_port=options[:port] || Mongodoc.PORT
			db_name=options[:db] || Mongodoc.DB
			raise "No valid database specified - set the default to anything other than the 'test' db via Mongodoc::configure or pass the :db option to this function" unless db_name_valid?(db_name)

			client=Mongodoc.client({:host => db_host, :port => db_port})
			return client[db_name] unless block
			begin
				block.call(client[db_name])
			ensure
				client.close
			end
		end

		def collection(options={}, &block)
			db_host=options[:host] || Mongodoc.HOST
			db_port=options[:port] || Mongodoc.PORT
			db_name=options[:db] || Mongodoc.DB
			collection_name=options[:collection]
			raise "Invalid collection specified" unless collection_name

			db=Mongodoc.db(:host => db_host, :port => db_port, :db => db_name)
			return db[collection_name] unless block
			begin
				block.call(db[collection_name])
			ensure
				db.connection.close
			end
		end

		def db_name_valid?(name=nil)
			return false if name.nil?
			return false if name.length <= 0
			return false if name == 'test' || name == 'tests'
			true
		rescue
			false
		end

		# implement this in subclasses to provide default for anchor
		def get_anchor_default(anchor)
			raise "No default anchor hash provided - you have to implement this in your subclasses via @paging_anchor_hash" unless @paging_anchor_hash
			
			@paging_anchor_hash[anchor]
			# {:value=>0, :name=>"foo0"} - provides the 'page 0' default for the given field for paging
		end

		def get_paged(options={})
			
			db_host=options[:host] || Mongodoc.HOST
			db_port=options[:port] || Mongodoc.PORT
			db_name=options[:db] || Mongodoc.DB
			collection_name=options[:collection]#bugbug - collection should default internally..?

			# the anchor is the document field you want to sort over.
			# it should be something unique and indexed so that paging is fast and distinct.
			# creation date might work if it's unique. a custom ID might be another good one.
			anchor=options[:anchor]
			raise "No anchor specified for paging" unless anchor

			# value for last element of previous page.
			# for page 0, should be the minimum value available for the anchor field.
			start_value_for_anchor=options[:anchor_start] || get_anchor_default(anchor)
			raise "No anchor value specified and no anchor default detected for paging" unless start_value_for_anchor

			asc_or_desc=:asc # bugbug - configurable?

			max_page_size=25 # bugbug - configurable?
			page_size=options[:page_size] || max_page_size # bugbug - configurable?

			raise "Page size must be a positive number not exceeding #{max_page_size}" unless(page_size <= max_page_size && page_size > 0)

			# on page 0, include the minimum value.
			# otherwise, exclude the start value, since it will have been the last element
			# of the previous page
			equivalency_symbol = start_value_for_anchor.equal?(get_anchor_default(anchor)) ? :$gte : :$gt

			col=Mongodoc.collection(:host=>db_host, :port=>db_port, :db=>db_name, :collection=>collection_name)

			# col.find({:value=>{:$gte=>30}}, {:limit=>20,:sort=>{:value=>:asc}}).each{|x| puts x}
			cursor=col.find( { anchor => { equivalency_symbol => start_value_for_anchor } }, { :limit => page_size, :sort => { anchor => asc_or_desc } } )
			
			#BUGBUG - this should return the actual subclass type
			results=[]
			cursor.each{|x| results << x}
			results
		end


	end#end of class
end