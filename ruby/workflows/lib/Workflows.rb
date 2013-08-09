# todo - fix the includes and references
require './Mongooz.rb'
require 'active_support/core_ext/hash/indifferent_access'


module Workflows

	@DEFAULT_DB='workflows'
	@DEFAULT_HOST='localhost'
	@DEFAULT_PORT=27017
	class << self
		attr_reader :DEFAULT_DB, :DEFAULT_HOST, :DEFAULT_PORT
		def defaults(options={})
			@DEFAULT_DB=options[:db] if options[:db]
			@DEFAULT_HOST=options[:host] if options[:host]
			@DEFAULT_PORT=options[:port] if options[:port]
		end
	end

	# class that all workflow related objects derive from
	class WorkflowHash < HashWithIndifferentAccess

		class << self
			def get_class_name_without_namespace(class_to_retrieve_name_from)
				return nil unless class_to_retrieve_name_from.respond_to?(:name)
				class_to_retrieve_name_from.name.split("::").last.downcase
			end

			# will override options in the given hash with defaults, where defaults
			# are specified
			def set_db_options(options)
				options[:collection]=options[:collection] || WorkflowHash.get_class_name_without_namespace(self)
				options[:db]=options[:db] || Workflows.DEFAULT_DB
				options[:host]=options[:host] || Workflows.DEFAULT_HOST
				options[:port]=options[:port] || Workflows.DEFAULT_PORT
			end

			def typified_result_hash_or_nil(hash_to_wrap)
				return nil unless hash_to_wrap.kind_of?(Hash)
				self.new.update(hash_to_wrap)
			end

			def db_get_with_id(options={})
				id=options[:_id]
				raise "Missing required :_id options parameter" unless id

				set_db_options(options)
				result=nil
				Mongooz::Base.collection(options) do |col|
					result=col.find_one(:_id => id)
				end

				typified_result_hash_or_nil(result)
			end

			def db_get_with_bson_string(bson_string, options={})
				bson_id=nil
				begin
					bson_id=BSON.ObjectId(bson_string)
				rescue
					raise "Expected string #{bson_string.to_s} to be a valid bson id"
				end
				raise "Failed to bson-ify #{bson_string.to_s}" if bson_id.nil?

				set_db_options(options)
				result=nil
				Mongooz::Base.collection(options) do |col|
					result=col.find_one(:_id => bson_id)
				end

				typified_result_hash_or_nil(result)
			end

			def db_get_paged(options={})

				max_page=100		# bugbug - configurable?
				max_page_size=25    # bugbug - configurable?
				page=options[:page] || 0
				raise "Page number must be a non-negative number not exceeding #{max_page}" unless page >= 0 && page < max_page

				page_size=options[:page_size] || max_page_size # bugbug - configurable?
				raise "Page size must be a positive number not exceeding #{max_page_size}" unless(page_size <= max_page_size && page_size > 0)

				num_to_skip=page * page_size
				set_db_options(options)

				results=[]
				Mongooz::Base.collection(options) do |col|

					# this is probably how best to do paging but it requires you keep track of
					# an anchor element, and a minimum anchor value, and the last element of the
					# previous page
					# col.find({:value=>{:$gte=>30}}, {:limit=>20,:sort=>{:value=>:asc}}).each{|x| puts x}

					# this is a lot easier to maintain, off the bat
					cursor=col.find( {}, {:limit => page_size, :skip=>num_to_skip})
					cursor.each do |next_result|
						typed_result=typified_result_hash_or_nil(next_result)
						results << typed_result if typed_result
					end
				end

				results
			end
		end

		def set_db_options(options)
			options[:collection]=options[:collection] || WorkflowHash.get_class_name_without_namespace(self.class)
			options[:db]=options[:db] || Workflows.DEFAULT_DB
			options[:host]=options[:host] || Workflows.DEFAULT_HOST
			options[:port]=options[:port] || Workflows.DEFAULT_PORT
		end

		def db_insert(raw_hash, options={})
			set_db_options(options)
			id=nil
			Mongooz::Base.collection(options) do |col|
				id=col.insert(raw_hash)
			end

			id
		end

		# probably not very useful - most of your update APIs should be targeted for performance.
		# this one will "replace" the given id with the given raw_hash.
		# you can use this API for upserts too, just pass :upsert=>true in the options hash.
		# behavior will differ on the upsert depending on whether or not the given id exists.
		def db_update(id, raw_hash, options={})
			set_db_options(options)
			err_hash=nil
			Mongooz::Base.collection(options) do |col|
				err_hash=col.update({:_id=>id}, raw_hash, options)
			end

			err_hash
		end


		def db_save(options={})
			success=false;
			id=self[:_id]
			if id.nil?
				db_insert(self, options)
				success=true
			else
				options[:upsert]=true
				err_hash=db_update(id, self, options)
				success=err_hash['n'].to_i > 0
			end

			success
		end

		# deletes everything matching delete_query from a collection.
		# 
		# the options hash takes db/connection/host/port, as well as any options to the delete api.
		#
		# delete_query has to be a hash.  if it's absent, this API will delete all docs
		# with _id=self[:_id].  If no such _id exists, raises an error.
		def db_delete(delete_query=nil, options={})
			query=nil
			if(delete_query.nil?)
				id=self[:_id]
				raise "Cannot delete without an _id" unless id
				query={:_id=>id}
			else
				raise "Delete query must be a hash" unless delete_query.kind_of?(Hash)
				query=delete_query
			end
			
			set_db_options(options)
			err_hash=nil
			Mongooz::Base.collection(options) do |col|
				err_hash=col.remove(query,options)
			end

			raise "Didn't get an error hash from delete api?" if err_hash.nil?
			raise "Didn't get an error hash that was a hash object from delete api?" unless err_hash.kind_of?(Hash)
			raise "Didn't get an error hash with an 'n' key from delete api?" unless err_hash['n']
			return err_hash['n']
		end

		# helper that raises errors if the given symbol is not present in the given hash
		def ensure_hash_has_symbol(hash_to_check, symbol_to_ensure)
			return unless symbol_to_ensure.kind_of?(Symbol) && hash_to_check.kind_of?(Hash)
			raise "Missing required :#{symbol_to_ensure.to_s} hash parameter" unless hash_to_check[symbol_to_ensure]
		end
	end
end