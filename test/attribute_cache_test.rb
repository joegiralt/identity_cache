require "test_helper"

class AttributeCacheTest < IdentityCache::TestCase
  NAMESPACE = IdentityCache::CacheKeyGeneration::DEFAULT_NAMESPACE

  def setup
    super
    AssociatedRecord.cache_attribute :name

    @parent = Item.create!(:title => 'bob')
    @record = @parent.associated_records.create!(:name => 'foo')
    @name_attribute_key = "#{NAMESPACE}attribute:AssociatedRecord:name:id:#{cache_hash(@record.id.to_s)}"
    @blob_key = "#{NAMESPACE}blob:AssociatedRecord:#{cache_hash("id:integer,item_id:integer,name:string")}:1"
  end

  def test_attribute_values_are_returned_on_cache_hits
    IdentityCache.cache.expects(:read).with(@name_attribute_key).returns('foo')
    assert_equal 'foo', AssociatedRecord.fetch_name_by_id(1)
  end

  def test_attribute_values_are_fetched_and_returned_on_cache_misses
    IdentityCache.cache.expects(:read).with(@name_attribute_key).returns(nil)
    Item.connection.expects(:select_value).with("SELECT `name` FROM `associated_records` WHERE `id` = 1 LIMIT 1").returns('foo')
    assert_equal 'foo', AssociatedRecord.fetch_name_by_id(1)
  end

  def test_attribute_values_are_stored_in_the_cache_on_cache_misses
    # Cache miss, so
    IdentityCache.cache.expects(:read).with(@name_attribute_key).returns(nil)

    # Grab the value of the attribute from the DB
    Item.connection.expects(:select_value).with("SELECT `name` FROM `associated_records` WHERE `id` = 1 LIMIT 1").returns('foo')

    # And write it back to the cache
    IdentityCache.cache.expects(:write).with(@name_attribute_key, 'foo').returns(nil)

    assert_equal 'foo', AssociatedRecord.fetch_name_by_id(1)
  end

  def test_nil_is_stored_in_the_cache_on_cache_misses
    # Cache miss, so
    IdentityCache.cache.expects(:read).with(@name_attribute_key).returns(nil)

    # Grab the value of the attribute from the DB
    Item.connection.expects(:select_value).with("SELECT `name` FROM `associated_records` WHERE `id` = 1 LIMIT 1").returns(nil)

    # And write it back to the cache
    IdentityCache.cache.expects(:write).with(@name_attribute_key, IdentityCache::CACHED_NIL).returns(nil)

    assert_equal nil, AssociatedRecord.fetch_name_by_id(1)
  end

  def test_cached_attribute_values_are_expired_from_the_cache_when_an_existing_record_is_saved
    IdentityCache.cache.expects(:delete).with(@name_attribute_key)
    IdentityCache.cache.expects(:delete).with(@blob_key)
    @record.save!
  end

  def test_cached_attribute_values_are_expired_from_the_cache_when_an_existing_record_with_changed_attributes_is_saved
    IdentityCache.cache.expects(:delete).with(@name_attribute_key)
    IdentityCache.cache.expects(:delete).with(@blob_key)
    @record.name = 'bar'
    @record.save!
  end

  def test_cached_attribute_values_are_expired_from_the_cache_when_an_existing_record_is_destroyed
    IdentityCache.cache.expects(:delete).with(@name_attribute_key)
    IdentityCache.cache.expects(:delete).with(@blob_key)
    @record.destroy
  end

  def test_cached_attribute_values_are_expired_from_the_cache_when_a_new_record_is_saved
    new_id = 2.to_s
    # primary index delete
    IdentityCache.cache.expects(:delete).with("#{NAMESPACE}blob:AssociatedRecord:#{cache_hash("id:integer,item_id:integer,name:string")}:#{new_id}")
    # attribute cache delete
    IdentityCache.cache.expects(:delete).with("#{NAMESPACE}attribute:AssociatedRecord:name:id:#{cache_hash(new_id)}")
    @parent.associated_records.create(:name => 'bar')
  end

  def test_fetching_by_attribute_delegates_to_block_if_transactions_are_open
    IdentityCache.cache.expects(:read).with(@name_attribute_key).never

    Item.connection.expects(:select_value).with("SELECT `name` FROM `associated_records` WHERE `id` = 1 LIMIT 1").returns('foo')

    @record.transaction do
      assert_equal 'foo', AssociatedRecord.fetch_name_by_id(1)
    end
  end

  def test_previously_stored_cached_nils_are_busted_by_new_record_saves
    assert_equal nil, AssociatedRecord.fetch_name_by_id(2)
    AssociatedRecord.create(:name => "Jim")
    assert_equal "Jim", AssociatedRecord.fetch_name_by_id(2)
  end
end
