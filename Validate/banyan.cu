#include <iostream>
#include <math.h>
#include <sstream>
#include <stdio.h>
#include <thrust/swap.h>
using namespace std;

// HOST helper function: get N given size of list
int getN(int size) {
  int N = 2; 
  while (N < size) {
    N = N*2;
  }
  return N;
}

// SHUFFLE kernel for N=pow(2,n) elements
__global__
void shuffleN(float *in, float *out, int size, ulong N) {
  // TO-DO: pull in shared memory
  // unsigned long ind_in  = threadIdx.x; // thread within block
  // unsigned long ind_in_base = blockIdx.x*blockDim.x; // block within col
  unsigned long ind_in_base = blockIdx.x*size; // block within col; accommodate fixed max threadNum=1024
  unsigned long ind_out; 
  unsigned long stride = blockDim.x; 
  for (unsigned long ind_in = threadIdx.x; ind_in < (unsigned long) size; ind_in += stride) {
    // ind_out = 2*(ind_in-ind_in % size/2);
    if (ind_in % 2 == 0) { // even 
      ind_out = ind_in/2;
    }  
    else {  // odd 
      ind_out = (size/2)+(ind_in/2);
    }
    out[ind_in_base+ind_in]=in[ind_in_base+ind_out];
    // using "out" as ping-pong; write back to "in"
    // __syncthreads();
    // in[ind_in_base+ind_in]=out[ind_in_base+ind_in];
  }
  __syncthreads();
  for (unsigned long ind_in = threadIdx.x; ind_in < (unsigned long) size; ind_in += stride) {
    in[ind_in_base+ind_in]=out[ind_in_base+ind_in];
  }
}


// BUTTERFLY kernel for N=pow(2,n) elements
__global__
void butterflyN(float *in, float *out, int size, ulong N) {
  // TO-DO: pull in shared memory
  unsigned long ind_in_base = blockIdx.x*size; // block within col; accommodate fixed max threadNum=1024
  unsigned long ind_out; 
  unsigned long stride = blockDim.x; 
  for (unsigned long ind_in = threadIdx.x; ind_in < (unsigned long) size; ind_in += stride) {
    if (ind_in < size/2) { // first half of list
      if (ind_in%2==0) // even
        ind_out = ind_in;
      else // odd
        ind_out = ind_in + (size/2 - 1);
    }  
    else {  // second half of list
      if (ind_in%2==0) // even
        ind_out = ind_in - (size/2 - 1);
      else //odd
        ind_out = ind_in;
    }
    out[ind_in_base+ind_in]=in[ind_in_base+ind_out];
  }
  // using "out" as ping-pong; write back to "in"
  __syncthreads();
  for (unsigned long ind_in = threadIdx.x; ind_in < (unsigned long) size; ind_in += stride) {
    in[ind_in_base+ind_in]=out[ind_in_base+ind_in];
  }
}

// COMPARE AND SWAP 
__global__
void compareAndSwap(float *in, bool *directions, int level, ulong N) {
  // TO-DO: pull in shared memory
  unsigned long stride = blockDim.x*gridDim.x; 
  // if (comp_ind < N) {
  for (unsigned long comp_ind = (unsigned long) blockDim.x*blockIdx.x+threadIdx.x;
       comp_ind < N;
       comp_ind += stride) {
    // STEP 0: Get direction of comparison
    // printf("ind_in: %d\n", ind_in);
    // printbinchar((char) ind_in & (0x1 << level));
    bool comp_bool = (bool)(comp_ind & (0x1 << level)); 
    // printf("for ind_in=%d comp_bool=%d\n", ind_in, comp_bool);
    directions[comp_ind] = comp_bool;
    // STEP 1: Write out results of comparisons
    unsigned long data0 = 2*comp_ind;
    unsigned long data1 = 2*comp_ind+1;
    // compare and swap based on comp_bool
    if ( (comp_bool && in[data0] < in[data1]) || (!comp_bool && in[data0] >= in[data1]) ) { 
        thrust::swap(*(in+data0), *(in+data1)); 
    }
  }
}

// int main(int argc, char** argv)
void benyan(float* x, float* y, bool* comparators, ulong N, uint n)
{
  // bitonic mergesort on batcher-banyan network
  int level = 0;
  int stage = 0;
  int substage = 0;
  int div;
  int threadNum;
  int compThreadNum = 512;
  int compBlockNum = min((long)65535,(N+compThreadNum-1)/compThreadNum); // max(blockNum)=65535
  printf("comparator blockNum=%d - threadNum=%d\n", compBlockNum, compThreadNum);
  while (stage < n) {
    while (substage <= stage) { 
      div = N/(pow(2,2+stage-substage));
      // printf("stage=%d - substage=%d - div=%d - level=%d\n", stage, substage, div, level);
      compareAndSwap<<<compThreadNum,compBlockNum>>>(x, comparators, level, N);
      cudaDeviceSynchronize();
      // printf("-> compare for stage=%d at level=%d\n", stage, level);
      if (stage < n-1) {
        threadNum = min((long)1024, N/div); 
        if (substage == 0) {
          shuffleN<<<div,threadNum>>>(x, y, N/div, N);
          cudaDeviceSynchronize();
          // printf("-> shuffle for stage=%d\n", stage);
          level++;
        }
        compareAndSwap<<<compThreadNum,compBlockNum>>>(x, comparators, level, N);
        cudaDeviceSynchronize();
        // printf("-> compare for stage=%d at level=%d\n", stage, level);
        butterflyN<<<div,threadNum>>>(x, y, N/div, N);
        cudaDeviceSynchronize();
        // printf("-> butterfly for stage=%d, substage=%d\n", stage, substage);
        substage++;
      }
      else {
        break;
      }
    }
    stage++;
    substage = 0;
  }

  return ;
}
