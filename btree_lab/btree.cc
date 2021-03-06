#include <assert.h>
#include "btree.h"
#include <stdio.h>
#include <string.h>

KeyValuePair::KeyValuePair()
{}


KeyValuePair::KeyValuePair(const KEY_T &k, const VALUE_T &v) : 
  key(k), value(v)
{}


KeyValuePair::KeyValuePair(const KeyValuePair &rhs) :
  key(rhs.key), value(rhs.value)
{}


KeyValuePair::~KeyValuePair()
{}


KeyValuePair & KeyValuePair::operator=(const KeyValuePair &rhs)
{
  return *( new (this) KeyValuePair(rhs));
}

BTreeIndex::BTreeIndex(SIZE_T keysize, 
		       SIZE_T valuesize,
		       BufferCache *cache,
		       bool unique) 
{
  superblock.info.keysize=keysize;
  superblock.info.valuesize=valuesize;
  buffercache=cache;
  // note: ignoring unique now
}

BTreeIndex::BTreeIndex()
{
  // shouldn't have to do anything
}


//
// Note, will not attach!
//
BTreeIndex::BTreeIndex(const BTreeIndex &rhs)
{
  buffercache=rhs.buffercache;
  superblock_index=rhs.superblock_index;
  superblock=rhs.superblock;
}

BTreeIndex::~BTreeIndex()
{
  // shouldn't have to do anything
}


BTreeIndex & BTreeIndex::operator=(const BTreeIndex &rhs)
{
  return *(new(this)BTreeIndex(rhs));
}


ERROR_T BTreeIndex::AllocateNode(SIZE_T &n)
{
  n=superblock.info.freelist;

  if (n==0) { 
    return ERROR_NOSPACE;
  }

  BTreeNode node;

  node.Unserialize(buffercache,n);

  assert(node.info.nodetype==BTREE_UNALLOCATED_BLOCK);

  superblock.info.freelist=node.info.freelist;

  superblock.Serialize(buffercache,superblock_index);

  buffercache->NotifyAllocateBlock(n);

  return ERROR_NOERROR;
}


ERROR_T BTreeIndex::DeallocateNode(const SIZE_T &n)
{
  BTreeNode node;

  node.Unserialize(buffercache,n);

  assert(node.info.nodetype!=BTREE_UNALLOCATED_BLOCK);

  node.info.nodetype=BTREE_UNALLOCATED_BLOCK;

  node.info.freelist=superblock.info.freelist;

  node.Serialize(buffercache,n);

  superblock.info.freelist=n;

  superblock.Serialize(buffercache,superblock_index);

  buffercache->NotifyDeallocateBlock(n);

  return ERROR_NOERROR;

}

ERROR_T BTreeIndex::Attach(const SIZE_T initblock, const bool create)
{
  ERROR_T rc;

  superblock_index=initblock;
  assert(superblock_index==0);

  if (create) {
    // build a super block, root node, and a free space list
    //
    // Superblock at superblock_index
    // root node at superblock_index+1
    // free space list for rest
    BTreeNode newsuperblock(BTREE_SUPERBLOCK,
			    superblock.info.keysize,
			    superblock.info.valuesize,
			    buffercache->GetBlockSize());
    newsuperblock.info.rootnode=superblock_index+1;
    newsuperblock.info.freelist=superblock_index+2;
    newsuperblock.info.numkeys=0;
    newsuperblock.info.height =0;

    buffercache->NotifyAllocateBlock(superblock_index);

    rc=newsuperblock.Serialize(buffercache,superblock_index);

    if (rc) { 
      return rc;
    }
    
    BTreeNode newrootnode(BTREE_ROOT_NODE,
			  superblock.info.keysize,
			  superblock.info.valuesize,
			  buffercache->GetBlockSize());
    newrootnode.info.rootnode=superblock_index+1;
    newrootnode.info.freelist=superblock_index+2;
    newrootnode.info.numkeys=0;

    buffercache->NotifyAllocateBlock(superblock_index+1);

    rc=newrootnode.Serialize(buffercache,superblock_index+1);

    if (rc) { 
      return rc;
    }

    for (SIZE_T i=superblock_index+2; i<buffercache->GetNumBlocks();i++) { 
      BTreeNode newfreenode(BTREE_UNALLOCATED_BLOCK,
			    superblock.info.keysize,
			    superblock.info.valuesize,
			    buffercache->GetBlockSize());
      newfreenode.info.rootnode=superblock_index+1;
      newfreenode.info.freelist= ((i+1)==buffercache->GetNumBlocks()) ? 0: i+1;
      
      rc = newfreenode.Serialize(buffercache,i);

      if (rc) {
	return rc;
      }

    }
  }

  // OK, now, mounting the btree is simply a matter of reading the superblock 

  return superblock.Unserialize(buffercache,initblock);
}
    

ERROR_T BTreeIndex::Detach(SIZE_T &initblock)
{
  return superblock.Serialize(buffercache,superblock_index);
}
 

ERROR_T BTreeIndex::InsertByPosition(const SIZE_T &node,
				     const BTreeOp op,
				     const KEY_T &key,
				     const VALUE_T &value)
{
  BTreeNode rootb;
  // BTreeNode& bref=rootb;
  ERROR_T rc;
  SIZE_T off=node;
  SIZE_T& offset = off;
  KEY_T testkey;
  // SIZE_T ptr;
  
  rc= rootb.Unserialize(buffercache,node);    
  
  if(rc!= ERROR_NOERROR){
    return rc;
  }
 
 // printf("leaf can have at most %i and interior node can at most have %i",rootb.info.GetNumSlotsAsInterior(),rootb.info.GetNumSlotsAsLeaf());
  if(superblock.info.height == 0){superblock.info.height += 1;}

  if(rootb.info.nodetype==BTREE_ROOT_NODE){
    //if it is root node and check is it is almost full
    //printf("I am a root node");
    if ((rootb.info.numkeys == rootb.info.GetNumSlotsAsInterior() && superblock.info.height >1)
	|| (rootb.info.numkeys == rootb.info.GetNumSlotsAsLeaf() && superblock.info.height == 1) ) {
      BTreeNode newrootnode;
      //BTreeNode& newrootref=newrootnode;
      SIZE_T newloc;
      SIZE_T& newptr=newloc;
      rc = AllocateNode(newptr);
      if(rc){return rc;}
      rc = newrootnode.Unserialize(buffercache,newptr);
      if(rc){return rc;}
      superblock.info.rootnode = newloc;
      
      newrootnode.info.nodetype = BTREE_ROOT_NODE;  //change the nodetype
      newrootnode.data = new char [newrootnode.info.GetNumDataBytes()];
      memset(newrootnode.data,0,newrootnode.info.GetNumDataBytes());
      newrootnode.info.numkeys = 0;

      rootb.info.nodetype = BTREE_INTERIOR_NODE;   //change the old root node to interior node
      if(superblock.info.height == 1){rootb.info.nodetype = BTREE_LEAF_NODE;}
      rc=rootb.Serialize(buffercache,offset);      //write the blocks
      if(rc != ERROR_NOERROR){return rc;}
      
      rc=newrootnode.Serialize(buffercache,newptr);
      if(rc!= ERROR_NOERROR){return rc;}
  
      rc=newrootnode.SetPtr(0,offset);   //set newrootnode.child1=old rootnode
      if(rc){return rc;}
      
      rc=newrootnode.Serialize(buffercache,newptr);  //write the new root node
      if(rc != ERROR_NOERROR){return rc;}	
      
//      superblock.info.rootnode = newptr;   //change the root node,should I write this into block?
      
      
      SIZE_T temp = 0;
    //  rc=newrootnode.GetPtr(0,ptr);
      BTreeSplitChild(newptr,temp,value);   //split the first child which used to be root
      superblock.info.height += 1;
      return BTreeInsertNoFull(newptr,key,value);


    } else {
      return BTreeInsertNoFull(node,key,value);
    }
  } else {
    cerr << "Insert without root node!" << endl;
    return ERROR_INSANE;
  }
  
  cerr << "Surprise exit"<<endl;
  return ERROR_IMPLBUG;
  
}

ERROR_T BTreeIndex::BTreeInsertNoFull(const SIZE_T &node,const KEY_T &key,const VALUE_T &value)
{
  BTreeNode b;
  //BTreeNode& bref=b;
  BTreeNode newnode;
  //BTreeNode& newref=newnode;
  ERROR_T rc;
  KEY_T testkey;
  SIZE_T ptr;
  VALUE_T testval;
	
  rc=b.Unserialize(buffercache,node);
  if(rc != ERROR_NOERROR){return rc;}
  SIZE_T i = b.info.numkeys;

  if(b.info.nodetype == BTREE_LEAF_NODE || (b.info.nodetype == BTREE_ROOT_NODE && superblock.info.height==1))
    {
      //		printf("still problems here?");
      if(b.info.nodetype == BTREE_ROOT_NODE)
	{
	  b.info.nodetype = BTREE_LEAF_NODE;
	}
      if(i>=1){
	b.info.numkeys += 1;
	rc=b.GetKey(i-1,testkey);
	if(rc){return rc;}
	while(i>=1 && (key< testkey || key == testkey))
	  {
	    if(key == testkey){return ERROR_INSANE;}
	    rc=b.SetKey(i,testkey);
	    if(rc){return rc;}
	    rc=b.GetVal(i-1,testval);
	    if(rc){return rc;}
	    rc=b.SetVal(i,testval);
	    i -= 1;
	    if(i>0){rc=b.GetKey(i-1,testkey);}
	  }
	if(key == testkey){ return ERROR_INSANE;}			
	rc=b.SetKey(i,key);
	if(rc){return rc;}
	rc=b.SetVal(i,value);
	if(rc){return rc;}
      }else{
	b.info.numkeys += 1;
	rc=b.SetKey(i,key);
	if(rc){return rc;}
	rc=b.SetVal(i,value);
	if(rc){return rc;}
      }
      if(superblock.info.height == 1)
	{
	  b.info.nodetype = BTREE_ROOT_NODE;
	}
      rc= b.Serialize(buffercache,node);
      if(rc != ERROR_NOERROR){return rc;}
      //		printf("insert nofull leaf reach bottom");
      return ERROR_NOERROR;
    }else{
    rc=b.GetKey(i-1,testkey);
    i -= 1;
   // printf("safe or not???");
    while( i>0 && key<testkey)
      {
	
 	i -= 1;
	
	rc=b.GetKey(i,testkey);

      }
    
    
    if(i==0 && (key<testkey || key == testkey)){i = i;}
    else if(key==testkey){i = i;}
	else{i += 1;}
    rc=b.GetPtr(i,ptr);
    if(rc){return rc;}
    rc=newnode.Unserialize(buffercache,ptr);
    if(rc != ERROR_NOERROR){return rc;}
   // printf("this is the middle of not leafnode");
    
    if((newnode.info.numkeys == newnode.info.GetNumSlotsAsInterior() && newnode.info.nodetype == BTREE_INTERIOR_NODE)
	||(newnode.info.nodetype == BTREE_LEAF_NODE && newnode.info.numkeys == newnode.info.GetNumSlotsAsLeaf()))
      {
	rc=BTreeSplitChild(node,i,value);
	if(rc){return rc;}
	rc=b.Unserialize(buffercache,node);
	if(rc){return rc;}
	rc=b.GetKey(i,testkey);
	if(rc){return rc;}

	if(!(key < testkey || key == testkey)){ i+=1;}
      }
    rc=b.GetPtr(i,ptr);
    if(rc){return rc;}

    return BTreeInsertNoFull(ptr,key,value);   //for further recursive
  }
}

//for internal and leaf nodes only
ERROR_T BTreeIndex::BTreeSplitChild(const SIZE_T &node, const SIZE_T offset,const VALUE_T &val)
{
	BTreeNode b;
	//BTreeNode& bref=b;
	BTreeNode c;
	//BTreeNode& cref=c;
	ERROR_T rc;
	KEY_T testkey;
	SIZE_T ptr;
	SIZE_T tempptr;
	VALUE_T tempval;
	SIZE_T tempb;

	tempb = node;
	
	rc = b.Unserialize(buffercache,node);     //get the node x to split its child
	if(rc!= ERROR_NOERROR){return rc;}
	
	BTreeNode newnode;
	//BTreeNode& newref=newnode;
	//SIZE_T newloc;
	SIZE_T newptr;
	rc = AllocateNode(newptr);
	if(rc){return rc;}
	rc = newnode.Unserialize(buffercache,newptr);    //new one node as z
	if(rc){return rc;}
	newnode.data = new char [newnode.info.GetNumDataBytes()];
        memset(newnode.data,0,newnode.info.GetNumDataBytes());
//	rc=newnode.Serialize(buffercache,newptr);
//	if(rc){return rc;}

	rc=b.GetPtr(offset,ptr);      //get y=node.key-offset
	if(rc){return rc;}
	
	rc=c.Unserialize(buffercache,ptr);  //get y as c
	if(rc!= ERROR_NOERROR){return rc;}
	
	newnode.info.nodetype = c.info.nodetype;
	 rc=newnode.Serialize(buffercache,newptr);
        if(rc){return rc;}
	
	if(c.info.nodetype != BTREE_LEAF_NODE)   //if y is a leaf node,if no we can cpoy the pointers
        {

		SIZE_T t = (b.info.GetNumSlotsAsInterior()+1)/2;   //defination for t
		SIZE_T tem = b.info.GetNumSlotsAsInterior()/2;
	    if(tem != t){
		newnode.info.numkeys = ((b.info.GetNumSlotsAsInterior()+1)/2) - 1;   //set node z size as t-1
	
		for(SIZE_T j=0;j< t-1;j++)   //copy the keys from t+1 to 2t-1
		{
			rc=c.GetKey(j + t ,testkey);
			if(rc){return rc;}
			rc=newnode.SetKey(j,testkey);
			if(rc){return rc;}
		}

	//if(c.info.nodetype != BTREE_LEAF_NODE)   //if y is a leaf node,if no we can cpoy the pointers
//	{
		for(SIZE_T j=0; j < t; j++)  //copy pointers from t+1 to 2t
		{
			rc=c.GetPtr(j + t ,tempptr);
			if(rc){return rc;}
			rc=newnode.SetPtr(j,tempptr);
			if(rc){return rc;}	
		}
	
		//c.info.numkeys= t-1;  //set node y size as t-1
		}
	   else{
		newnode.info.numkeys = t -1;
		for(SIZE_T j = 0; j<t-1;j++)
		{
			rc=c.GetKey(j+t+1,testkey);
			if(rc){return rc;}
			rc=newnode.SetKey(j,testkey);
			if(rc){return rc;}
		}
		for(SIZE_T j=0;j<t;j++)
		{
			rc=c.GetPtr(j+t+1,tempptr);
			if(rc){return rc;}
			rc=newnode.SetPtr(j,tempptr);
			if(rc){return rc;}
		}
	//	c.info.numkeys = t;
	   }
		
	}else{
		
 		SIZE_T l = (c.info.GetNumSlotsAsLeaf() +1) / 2;   //upper bound and lower bound?
		SIZE_T lem = c.info.GetNumSlotsAsLeaf()/2;
 	   
	//	newnode.info.numkeys = l - 1;
	    if(lem != l){
		newnode.info.numkeys = l - 1;
		for(SIZE_T j=0;j<l-1;j++)
		{
			rc=c.GetKey(j + l,testkey);
			if(rc){return rc;}
			rc=newnode.SetKey(j,testkey);
			if(rc){return rc;}
//		}
	
//		for(SIZE_T j=0;j<l-1;j++)
//		{
			rc=c.GetVal(j + l, tempval);
			if(rc){return rc;}
			rc=newnode.SetVal(j,tempval);
			if(rc){return rc;}
		}
		c.info.numkeys=l;  //set leaf y size as t (one more than z)
		}else{
		
		newnode.info.numkeys = l;
		for(SIZE_T j=0;j<l;j++)
		{
			rc=c.GetKey(j+l,testkey);
			if(rc){return rc;}
			rc=newnode.SetKey(j,testkey);
			if(rc){return rc;}
			rc=c.GetVal(j+l,tempval);
			if(rc){return rc;}
			rc=newnode.SetVal(j,tempval);
			if(rc){return rc;}
		}
		c.info.numkeys = l;
		}
	}
	
	b.info.numkeys += 1;
	if(b.info.numkeys != 1){
	
		for(SIZE_T j=b.info.numkeys-1;j>=(offset + 1);j--)   //make x's pointers after off+1 move back by 1
		{
			rc=b.GetPtr(j,tempptr);
			if(rc){return rc;}
			rc=b.SetPtr(j+1,tempptr);
			if(rc){return rc;}
			if(j==0){break;}
		}

		rc=b.SetPtr(offset+1,newptr);  //set x's off+1 pointer points to newnode
		if(rc){return rc;}

		for(SIZE_T j=b.info.numkeys-2;j>=offset;j--)   //make x's keys after off move back by 1
		{
			rc=b.GetKey(j,testkey);
			if(rc){return rc;}
			rc=b.SetKey(j+1,testkey);
			if(rc){return rc;}
			if(j==0){break;}
		}
	}

	if(c.info.nodetype != BTREE_LEAF_NODE) 
	{
		SIZE_T t = (b.info.GetNumSlotsAsInterior()+1)/2;
		SIZE_T tem = b.info.GetNumSlotsAsInterior()/2;
	     if(tem != t){ 
		rc=c.GetKey(t-1,testkey);            //set x's off key as y's t key
		if(rc){return rc;}
		c.info.numkeys = t-1;
		}else{
		rc = c.GetKey(t,testkey);
		if(rc){return rc;}
		c.info.numkeys = t;
		}
	}else{
		 SIZE_T l = (c.info.GetNumSlotsAsLeaf()+1) / 2; 
	//	SIZE_T lem = c.info.GetNumSlotsAsLeaf()/2;
		rc=c.GetKey(l-1,testkey);
		if(rc){return rc;}
		
	}
	rc=b.SetKey(offset,testkey);
	if(rc){return rc;}
	rc=b.SetPtr(offset+1,newptr);
	if(rc){return rc;}

//	b.info.numkeys += 1;
//	superblock.info.height += 1;
	
	rc=b.Serialize(buffercache,node); //write b which is x
	if(rc){return rc;}
	rc=c.Serialize(buffercache,ptr); //write c which is y
	if(rc){return rc;}
	return newnode.Serialize(buffercache,newptr); //write newnode which is z

}







ERROR_T BTreeIndex::LookupOrUpdateInternal(const SIZE_T &node,
					   const BTreeOp op,
					   const KEY_T &key,
					   VALUE_T &value)
{
  BTreeNode b;
  ERROR_T rc;
  SIZE_T offset;
  KEY_T testkey;
  SIZE_T ptr;
  //SIZE_T& tempkey = key;
 // printf("where you can get??");
  rc= b.Unserialize(buffercache,node);

  if (rc!=ERROR_NOERROR) { 
    return rc;
  }
  if(superblock.info.height == 1){b.info.nodetype = BTREE_LEAF_NODE;}
  switch (b.info.nodetype) { 
  case BTREE_ROOT_NODE:
  case BTREE_INTERIOR_NODE:
    // Scan through key/ptr pairs
    //and recurse if possible
    for (offset=0;offset<b.info.numkeys;offset++) { 
      rc=b.GetKey(offset,testkey);
//	printf("get here");
      if (rc) {  return rc; }
      if (key<testkey || key==testkey) {
	// OK, so we now have the first key that's larger
	// so we ned to recurse on the ptr immediately previous to 
	// this one, if it exists
	rc=b.GetPtr(offset,ptr);
	if (rc) { return rc; }
	return LookupOrUpdateInternal(ptr,op,key,value);
      }
    }
    // if we got here, we need to go to the next pointer, if it exists
    if (b.info.numkeys>0) { 
      rc=b.GetPtr(b.info.numkeys,ptr);
      if (rc) { return rc; }
      return LookupOrUpdateInternal(ptr,op,key,value);
    } else {
      // There are no keys at all on this node, so nowhere to go
      return ERROR_NONEXISTENT;
    }
    break;
  case BTREE_LEAF_NODE:
    // if(superblock.info.height == 1){b.info.nodetype = BTREE_ROOT_NODE;}
    // Scan through keys looking for matching value
    for (offset=0;offset<b.info.numkeys;offset++) { 
      rc=b.GetKey(offset,testkey);
      if (rc) {  return rc; }
      if (testkey==key) { 
	if (op==BTREE_OP_LOOKUP) { 
	  rc=b.GetVal(offset,value);
	  if(superblock.info.height == 1){b.info.nodetype = BTREE_ROOT_NODE;}
	 return rc;
	} else { 
	  // BTREE_OP_UPDATE
	  // WRITE ME
	  rc=b.SetVal(offset,value);  //added
	  if(rc){return rc;}
	  if(superblock.info.height == 1){b.info.nodetype = BTREE_ROOT_NODE;}
	  return b.Serialize(buffercache,node);
	}
      }
    }
    return ERROR_NONEXISTENT;
    break;
  default:
    // We can't be looking at anything other than a root, internal, or leaf
    return ERROR_INSANE;
    break;
  }  

  return ERROR_INSANE;
}


static ERROR_T PrintNode(ostream &os, SIZE_T nodenum, BTreeNode &b, BTreeDisplayType dt, SIZE_T height)
{
  KEY_T key;
  VALUE_T value;
  SIZE_T ptr;
  SIZE_T offset;
  ERROR_T rc;
  unsigned i;

  if (dt==BTREE_DEPTH_DOT) { 
    os << nodenum << " [ label=\""<<nodenum<<": ";
  } else if (dt==BTREE_DEPTH) {
    os << nodenum << ": ";
  } else {
  }
 
  if(height == 1){b.info.nodetype = BTREE_LEAF_NODE;}

  switch (b.info.nodetype) { 
  case BTREE_ROOT_NODE:
  case BTREE_INTERIOR_NODE:
    if (dt==BTREE_SORTED_KEYVAL) {
    } else {
      if (dt==BTREE_DEPTH_DOT) { 
      } else { 
	os << "Interior: ";
      }
      for (offset=0;offset<=b.info.numkeys;offset++) { 
	rc=b.GetPtr(offset,ptr);
	if (rc) { return rc; }
	os << "*" << ptr << " ";
	// Last pointer
	if (offset==b.info.numkeys) break;
	rc=b.GetKey(offset,key);
	if (rc) {  return rc; }
	for (i=0;i<b.info.keysize;i++) { 
	  os << key.data[i];
	}
	os << " ";
      }
    }
    break;
  case BTREE_LEAF_NODE:
    if (dt==BTREE_DEPTH_DOT || dt==BTREE_SORTED_KEYVAL) { 
    } else {
      os << "Leaf: ";
    }
    for (offset=0;offset<b.info.numkeys;offset++) { 
      if (offset==0) { 
	// special case for first pointer
	rc=b.GetPtr(offset,ptr);
	if (rc) { return rc; }
	if (dt!=BTREE_SORTED_KEYVAL) { 
	  os << "*" << ptr << " ";
	}
      }
      if (dt==BTREE_SORTED_KEYVAL) { 
	os << "(";
      }
      rc=b.GetKey(offset,key);
      if (rc) {  return rc; }
      for (i=0;i<b.info.keysize;i++) { 
	os << key.data[i];
      }
      if (dt==BTREE_SORTED_KEYVAL) { 
	os << ",";
      } else {
	os << " ";
      }
      rc=b.GetVal(offset,value);
      if (rc) {  return rc; }
      for (i=0;i<b.info.valuesize;i++) { 
	os << value.data[i];
      }
      if (dt==BTREE_SORTED_KEYVAL) { 
	os << ")\n";
      } else {
	os << " ";
      }
    }
   if(height == 1){b.info.nodetype = BTREE_ROOT_NODE;}	
    break;
  default:
    if (dt==BTREE_DEPTH_DOT) { 
      os << "Unknown("<<b.info.nodetype<<")";
    } else {
      os << "Unsupported Node Type " << b.info.nodetype ;
    }
  }
  if (dt==BTREE_DEPTH_DOT) { 
    os << "\" ]";
  }
  return ERROR_NOERROR;
}
  
ERROR_T BTreeIndex::Lookup(const KEY_T &key, VALUE_T &value)
{
  return LookupOrUpdateInternal(superblock.info.rootnode, BTREE_OP_LOOKUP, key, value);
}

ERROR_T BTreeIndex::Insert(const KEY_T &key,const  VALUE_T &value)
{
  // WRITE ME
 // printf("get insert here");
  return InsertByPosition(superblock.info.rootnode,BTREE_OP_INSERT, key, value);  //added
  //return ERROR_UNIMPL;
}
  
ERROR_T BTreeIndex::Update(const KEY_T &key,const  VALUE_T &value)
{
  // WRITE ME
  VALUE_T val = value;
  return LookupOrUpdateInternal(superblock.info.rootnode, BTREE_OP_UPDATE, key, val);
  //added
}

  
ERROR_T BTreeIndex::Delete(const KEY_T &key)
{
  // This is optional extra credit 
  //
  // 
  return ERROR_UNIMPL;
}

  
//
//
// DEPTH first traversal
// DOT is Depth + DOT format
//

ERROR_T BTreeIndex::DisplayInternal(const SIZE_T &node,
				    ostream &o,
				    BTreeDisplayType display_type) const
{
  KEY_T testkey;
  SIZE_T ptr;
  BTreeNode b;
  ERROR_T rc;
  SIZE_T offset;
  SIZE_T height = superblock.info.height;
  rc= b.Unserialize(buffercache,node);

  if (rc!=ERROR_NOERROR) { 
    return rc;
  }

  rc = PrintNode(o,node,b,display_type,height);
  
  if (rc) { return rc; }

  if (display_type==BTREE_DEPTH_DOT) { 
    o << ";";
  }

  if (display_type!=BTREE_SORTED_KEYVAL) {
    o << endl;
  }
  if(superblock.info.height==1){b.info.nodetype = BTREE_LEAF_NODE;}
  switch (b.info.nodetype) { 
  case BTREE_ROOT_NODE:
  case BTREE_INTERIOR_NODE:
    if (b.info.numkeys>0) { 
      for (offset=0;offset<=b.info.numkeys;offset++) { 
	rc=b.GetPtr(offset,ptr);
	if (rc) { return rc; }
	if (display_type==BTREE_DEPTH_DOT) { 
	  o << node << " -> "<<ptr<<";\n";
	}
	rc=DisplayInternal(ptr,o,display_type);
	if (rc) { return rc; }
      }
    }
    return ERROR_NOERROR;
    break;
  case BTREE_LEAF_NODE:
    if(superblock.info.height == 1){b.info.nodetype = BTREE_ROOT_NODE;}
    return ERROR_NOERROR;
    break;
  default:
    if (display_type==BTREE_DEPTH_DOT) { 
    } else {
      o << "Unsupported Node Type " << b.info.nodetype ;
    }
    return ERROR_INSANE;
  }

  return ERROR_NOERROR;
}


ERROR_T BTreeIndex::Display(ostream &o, BTreeDisplayType display_type) const
{
  ERROR_T rc;
  if (display_type==BTREE_DEPTH_DOT) { 
    o << "digraph tree { \n";
  }
  rc=DisplayInternal(superblock.info.rootnode,o,display_type);
  if (display_type==BTREE_DEPTH_DOT) { 
    o << "}\n";
  }
  return ERROR_NOERROR;
}


ERROR_T BTreeIndex::SanityCheck() const
{
  set<SIZE_T> visited;
  SIZE_T root=superblock.info.rootnode;
  return check_Tree(visited,root);
}
  

ERROR_T BTreeIndex::check_Tree(set<SIZE_T> visited, const SIZE_T &node) const{
  BTreeNode b;
  ERROR_T rc;
  SIZE_T ptr;
  SIZE_T& ptr_ref = ptr;
  SIZE_T offset;

  if (visited.count(node)) {
	 return ERROR_INSANE;
  } else {
	 visited.insert(node);
  }
  

  rc = b.Unserialize(buffercache, node);
  if(rc) {return rc;}

  switch(b.info.nodetype){
  case BTREE_ROOT_NODE:
  case BTREE_INTERIOR_NODE:

    if (b.info.numkeys > b.info.GetNumSlotsAsInterior()) {
      return ERROR_INSANE;
    }

    for(offset=0; offset<=b.info.numkeys; offset++){
      rc = b.GetPtr(offset, ptr_ref);
      if(rc) {return rc;}
      rc = check_Tree(visited, ptr_ref);
      if (rc) { return rc; }
    }
    return ERROR_NOERROR;
    break;
  case BTREE_LEAF_NODE:
    if (b.info.numkeys > b.info.GetNumSlotsAsLeaf()) {
      return ERROR_INSANE;
    }
    return ERROR_NOERROR;
    break;
  default:
    return ERROR_INSANE;
    break;
  }
  return ERROR_INSANE;
}




ostream & BTreeIndex::Print(ostream &os) const
{
  // WRITE ME
  return os;
}




