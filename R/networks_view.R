#'Update integrative pathway analysis for new input list
#'@description used for integrative analysis
#'as well as general pathways analysis for meta-analysis results
#'@usage UpdateIntegPathwayAnalysis(mSetObj=NA, qids, file.nm, 
#'topo="dc", enrich="hyper", libOpt="integ")
#'@param mSetObj Input name of the created mSet Object
#'@param qids Input the query IDs
#'@param file.nm Input the name of the file
#'@param topo Select the mode for topology analysis: Degree Centrality ("dc") measures the number of links that connect to a node
#'(representing either a gene or metabolite) within a pathway; Closeness Centrality ("cc") measures the overall distance from a given node
#'to all other nodes in a pathway; Betweenness Centrality ("bc")measures the number of shortest paths from all nodes to all the others that pass through a given node within a pathway.
#'@param enrich Method to perform over-representation analysis (ORA) based on either hypergenometrics analysis ("hyper")
#' or Fisher's exact method ("fisher").
#'@param libOpt Select the different modes of pathways, either the gene-metabolite mode ("integ") which allows for joint-analysis
#' and visualization of both significant genes and metabolites or the gene-centric ("genetic") and metabolite-centric mode ("metab") which allows users
#' to identify enriched pathways driven by significant genes or metabolites, respectively.
#'@author Jeff Xia \email{jeff.xia@mcgill.ca}
#'McGill University, Canada
#'License: GNU GPL (>= 2)
#'@export
UpdateIntegPathwayAnalysis <- function(mSetObj=NA, qids, file.nm, topo="dc", enrich="hyper", libOpt="integ",vis.type=""){
  mSetObj <- .get.mSet(mSetObj);
  # make sure this is annotated   
  if(is.null(mSetObj$org)){
    AddErrMsg("It appears that data is not annotated yet - unknown organism and ID types! Please use other modules (pathway/network) to access this function.");
    return(0);
  }
  sub.dir <- paste0("kegg/jointpa/",libOpt);
  destfile <- paste0(mSetObj$org, ".qs");
  current.kegglib <<- .get.my.lib(destfile, sub.dir);
  qs::qsave(current.kegglib, "current.kegglib.qs");

  load_igraph();

  qids <- do.call(rbind, strsplit(qids, "; ", fixed=TRUE));
  idtypes <- unlist(sapply(qids, function(x) substring(x, 1, 1) == "C"))
  qcmpds <- qids[idtypes]
  qgenes <- qids[!idtypes]

  set.size <- length(current.kegglib$mset.list);
  ms.list <- lapply(current.kegglib$mset.list, function(x){strsplit(x, " ", fixed=TRUE)});
  current.universe <- unique(unlist(ms.list));

  # prepare for the result table
  res.mat<-matrix(0, nrow=set.size, ncol=7);
  rownames(res.mat)<-names(current.kegglib$path.ids);
  colnames(res.mat)<-c("Total", "Expected", "Hits", "Pval", "Topology", "PVal.Z",  "Topo.Z");

  mSetObj$dataSet$pathinteg.method <- libOpt;
  mSetObj$dataSet$path.mat <- NULL;

  if(libOpt == "genetic"){
    gene.vec <- paste(mSetObj$org, ":", qgenes, sep="");
    ora.vec <- gene.vec;
    ora.vec.ids <- c(qgenes);
    uniq.count <- current.kegglib$uniq.gene.count;
    uniq.len <- current.kegglib$gene.counts;

  }else if(libOpt == "metab"){
    cmpd.vec <- paste("cpd:", qcmpds, sep="");
    ora.vec <- cmpd.vec;
    ora.vec.ids <- c(qcmpds);
    uniq.count <- current.kegglib$uniq.cmpd.count
    uniq.len <- current.kegglib$cmpd.counts;

  }else{ # integ

    cmpd.vec <- paste("cpd:", qcmpds, sep="");
    gene.vec <- paste(mSetObj$org, ":", qgenes, sep="");
    ora.vec <- c(cmpd.vec, gene.vec);
    ora.vec.ids <- c(qcmpds, qgenes);

    uniq.count <- current.kegglib$uniq.cmpd.count
    uniq.len <- current.kegglib$cmpd.counts;
    uniq.count <- uniq.count + current.kegglib$uniq.gene.count;
    uniq.len <- uniq.len + current.kegglib$gene.counts;

  }
  # need to cut to the universe covered by the pathways, not all genes
  ora.vec <- ora.vec[ora.vec %in% current.universe]
  q.size <- length(ora.vec);
  # note, we need to do twice one for nodes (for plotting)
  # one for query for calculating, as one node can be associated with multiple matches
  # get the matched nodes on each pathway
  hits.path <- lapply(ms.list, function(x) {unlist(lapply(x, function(var){any(var%in%ora.vec);}),use.names=FALSE)});
  names(hits.path) <- current.kegglib$path.ids;

  # get the matched query for each pathway
  hits.query <- lapply(ms.list, function(x) {ora.vec%in%unlist(x);});

  hit.num <- unlist(lapply(hits.query, function(x){sum(x)}), use.names=FALSE);

  if(sum(hit.num) == 0){
    AddErrMsg("No hits found for your input!");
    return(0);
  }

  set.num <- uniq.len;
  res.mat[,1] <- set.num;
  res.mat[,2] <- q.size*(set.num/uniq.count);
  res.mat[,3] <- hit.num;

  # use lower.tail = F for P(X>x)
  if(enrich=="hyper"){
    res.mat[,4] <- phyper(hit.num-1, set.num, uniq.count-set.num, q.size, lower.tail=F);
  }else if(enrich == "fisher"){
    res.mat[,4] <- GetFisherPvalue(hit.num, q.size, set.num, uniq.count);
  }else{
    AddErrMsg(paste("Not defined enrichment method:", enrich));
    return(0);
  }

  # toplogy test
  if(topo == "bc"){
    imp.list <- current.kegglib$bc;
  }else if(topo == "dc"){
    imp.list <- current.kegglib$dc;
  }else if(topo == "cc"){
    imp.list <- current.kegglib$cc;
  }else{
    AddErrMsg(paste("Not defined topology method:", topo));
    return(0);
  }

  # now, perform topological analysis
  # calculate the sum of importance
  res.mat[,5] <- mapply(function(x, y){sum(x[y])}, imp.list, hits.path);

  # now add two more columns for the scaled values
  res.mat[,6] <- scale(-log(res.mat[,4]));
  res.mat[,7] <- scale(res.mat[,5]);

  # now, clean up result, synchronize with hit.query
  res.mat <- res.mat[hit.num>0,,drop = F];
  hits.query <- hits.query[hit.num>0];

  if(nrow(res.mat)> 1){
    # order by p value
    ord.inx <- order(res.mat[,4]);
    res.mat <- signif(res.mat[ord.inx,],3);
    hits.query <- hits.query[ord.inx];

    imp.inx <- res.mat[,4] <= 0.05;
    if(sum(imp.inx) < 10){ # too little left, give the top ones
      topn <- ifelse(nrow(res.mat) > 10, 10, nrow(res.mat));
      res.mat <- res.mat[1:topn,];
      hits.query <- hits.query[1:topn];
    }else{
      res.mat <- res.mat[imp.inx,];
      hits.query <- hits.query[imp.inx];
      if(sum(imp.inx) > 120){
        # now, clean up result, synchronize with hit.query
        res.mat <- res.mat[1:120,];
        hits.query <- hits.query[1:120];
      }
    }
  }

  hits.names <- lapply(hits.query, function(x) ora.vec.ids[which(x == TRUE)]);

  #get gene symbols
  resTable <- data.frame(Pathway=rownames(res.mat), res.mat);

  fun.anot = hits.names; names(fun.anot) <- resTable[,1];
  fun.pval = resTable$Pval; if(length(fun.pval) ==1) { fun.pval <- matrix(fun.pval) };
  hit.num = paste0(resTable$Hits,"/",resTable$Total); if(length(hit.num) ==1) { hit.num <- matrix(hit.num) };
  current.setlink <- "http://www.genome.jp/kegg-bin/show_pathway?";

  json.res <- list(
              fun.link = current.setlink[1],
              fun.anot = fun.anot,
              #fun.ids = fun.ids,
              fun.pval = fun.pval,
              hit.num = hit.num
  );
  json.mat <- rjson::toJSON(json.res);
  json.nm <- paste(file.nm, ".json", sep="");

  sink(json.nm)
  cat(json.mat);
  sink();

  # write csv
  fun.hits <<- hits.query;
  fun.pval <<- fun.pval;
  hit.num <<- resTable$Hits;
  csv.nm <- paste(file.nm, ".csv", sep="");

  if(is.null(mSetObj$imgSet$enrTables)){
      mSetObj$imgSet$enrTables <- list();
  }

  mSetObj$imgSet$enrTables[[vis.type]] <- list();
  mSetObj$imgSet$enrTables[[vis.type]]$table <- resTable;
  mSetObj$imgSet$enrTables[[vis.type]]$res.mat <- res.mat;

  mSetObj$imgSet$enrTables[[vis.type]]$library <- libOpt;
  mSetObj$imgSet$enrTables[[vis.type]]$algo <- "Overrepresentation Analysis";
  .set.mSet(mSetObj);


  fast.write.csv(resTable, file=csv.nm, row.names=F);
  return(1);
}

#'Create igraph from the edgelist saved from graph DB and decompose into subnets
#'@description Function for the network explorer module, prepares user's data for network exploration.
#'@param mSetObj Input name of the created mSet Object
#'@export
#'@import igraph
CreateGraph <- function(mSetObj=NA){

  mSetObj <- .get.mSet(mSetObj);

  if(.on.public.web){
    load_igraph()
  }

  net.type <- pheno.net$table.nm;
  node.list <- pheno.net$node.data;
  edge.list <- pheno.net$edge.data;

  seed.proteins <- pheno.net$seeds;
  if(net.type == "dspc"){
    if(nrow(edge.list) < 1000){
      top.percent <- round(nrow(edge.list)*0.2);
      top.edge <- sort(unique(edge.list$Pval))[1:top.percent]; #default only show top 20% significant edges when #edges<1000
    }else{                                                    #default only show top 100 significant edges when #edges>1000   
      top.edge <- sort(edge.list$Pval)[1:100];
    }
    top.inx <- match(edge.list$Pval, top.edge);
    topedge.list <- edge.list[!is.na(top.inx), ,drop=F];
    overall.graph <-simplify(graph_from_data_frame(topedge.list, directed=FALSE, vertices=NULL), edge.attr.comb="first");
    seed.graph <<- seed.proteins;
  }else{
    overall.graph <- simplify(graph_from_data_frame(edge.list, directed=FALSE, vertices=node.list), remove.multiple=FALSE);
    # add node expression value
    #newIDs <- names(seed.expr);
    newIDs <- seed.graph;
    match.index <- match(V(overall.graph)$name, newIDs);
    expr.vals <- seed.expr[match.index];
    overall.graph <- set.vertex.attribute(overall.graph, "abundance", index = V(overall.graph), value = expr.vals);
  }

  hit.inx <- seed.proteins %in% node.list[,1];
  seed.proteins <<- seed.proteins[hit.inx];

  substats <- DecomposeGraph(overall.graph);
  overall.graph <<- overall.graph;

  #tmp-test-js; mSetObj <- PlotNetwork(mSetObj, network.type);

  if(.on.public.web){
    mSetObj <- .get.mSet(mSetObj);
    if(!is.null(substats)){
      return(c(length(seed.graph), length(seed.proteins), nrow(node.list), nrow(edge.list), length(pheno.comps), substats));
    }else{
      return(0);
    }
  }else{
    return(.set.mSet(mSetObj));
  }
}

###
### Utility functions
###

# Utility function to plot network for analysis report (CreateGraph)
PlotNetwork <- function(mSetObj=NA, imgName, format="png", dpi=default.dpi, width=NA){

  mSetObj <- .get.mSet(mSetObj);

  img.Name = paste(imgName, "_dpi", dpi, ".", format, sep="");

  if(is.na(width)){
    w <- 10;
  }else if(width == 0){
    w <- 8;

  }else{
    w <- width;
  }

  h <- w;

  mSetObj$imgSet$networkplot <- img.Name

  nodeColors <- rep("lightgrey", length(V(overall.graph)))
  idx.cmpd <- as.vector(sapply(names(V(overall.graph)), function(x) substring(x,0,1) == "C"))
  idx.genes <- names(V(overall.graph)) %in% mSetObj$dataSet$gene
  nodeColors[idx.cmpd] <- "orange"
  nodeColors[idx.genes] <- "#306EFF"
  V(overall.graph)$color <- nodeColors

  # annotation
  nms <- V(overall.graph)$name;
  hit.inx <- match(nms, pheno.net$node.data[,1]);
  lbls <- pheno.net$node.data[hit.inx,2];
  V(overall.graph)$name <- as.vector(lbls);

  Cairo::Cairo(file = img.Name, unit="in", dpi=dpi, width=w, height=h, type=format, bg="white");
  plot(overall.graph)
  text(1,1, "Entrez gene ", col="#306EFF")
  text(1,0.9, "KEGG compound ", col="orange")
  if(sum(nodeColors == "lightgrey") > 0){
    text(1,0.8, "OMIM disease ", col="lightgrey")
  }
  dev.off();

  if(.on.public.web==FALSE){
    return(.set.mSet(mSetObj));
  }else{
    .set.mSet(mSetObj);
  }
}

PrepareNetwork <- function(net.nm, json.nm){
  convertIgraph2JSON(net.nm, json.nm);
  current.net.nm <<- net.nm;
  return(1);
}

# from node ID (uniprot) return entrez IDs (one to many)
GetNodeEntrezIDs <- function(uniprotID){
  enIDs <- current.anot[uniprotID];
  enIDs <- paste(enIDs, collapse="||");
  enIDs;
}

GetNodeEmblEntrezIDs <- function(emblprotein){
  enIDs <- current.anot[emblprotein];
  enIDs <- paste(enIDs, collapse="||");
  enIDs;
}

GetNodeIDs <- function(){
  V(overall.graph)$name;
}

GetNodeNames <- function(){
  V(overall.graph)$Label;
}

GetNodeDegrees <- function(){
  igraph::degree(overall.graph);
}

GetNodeBetweenness <- function(){
  round(betweenness(overall.graph, directed=F, normalized=F), 2);
}

DecomposeGraph <- function(gObj, minNodeNum=3, maxNetNum=10){

  # now decompose to individual connected subnetworks
  comps <- igraph::decompose.graph(gObj, min.vertices=minNodeNum);
  if(length(comps) == 0){
    msg <- paste("No subnetwork was identified with at least", minNodeNum, "nodes!");
    AddErrMsg(msg);
    return(NULL);
  }

  # first compute subnet stats
  net.stats <- ComputeSubnetStats(comps);
  ord.inx <- order(net.stats[,1], decreasing=TRUE);
  net.stats <- net.stats[ord.inx,];
  comps <- comps[ord.inx];
  names(comps) <- rownames(net.stats) <- paste("subnetwork", 1:length(comps), sep="");

  # note, we report stats for all nets (at least 3 nodes);
  hit.inx <- net.stats$Node >= minNodeNum;
  comps <- comps[hit.inx];

  # in case too many
  if(length(comps) > maxNetNum){
     comps <- comps[1:maxNetNum];
  }

  # now record
  pheno.comps <<- comps;
  net.stats <<- net.stats;
  sub.stats <- unlist(lapply(comps, vcount));
  return(sub.stats);
}

PrepareSubnetDownloads <- function(nm){
  g <- pheno.comps[[nm]];
  # need to update graph so that id is compound names rather than ID
  V(g)$name <- as.character(doID2LabelMapping(V(g)$name));
  saveNetworkInSIF(g, nm);
}

ComputeSubnetStats <- function(comps){
  library(igraph);
  net.stats <- as.data.frame(matrix(0, ncol = 3, nrow = length(comps)));
  colnames(net.stats) <- c("Node", "Edge", "Query");
  for(i in 1:length(comps)){
    g <- comps[[i]];
    net.stats[i,] <- c(vcount(g),ecount(g),sum(seed.proteins %in% V(g)$name));
  }
  return(net.stats);
}

UpdateSubnetStats <- function(){
  old.nms <- names(pheno.comps);
  net.stats <- ComputeSubnetStats(pheno.comps);
  ord.inx <- order(net.stats[,1], decreasing=TRUE);
  net.stats <- net.stats[ord.inx,];
  rownames(net.stats) <- old.nms[ord.inx];
  net.stats <<- net.stats;
}

GetNetsName <- function(){
  rownames(net.stats);
}

GetNetsNameString <- function(){
  paste(rownames(net.stats), collapse="||");
}

GetNetsEdgeNum <- function(){
  as.numeric(net.stats$Edge);
}

GetNetsNodeNum <- function(){
  as.numeric(net.stats$Node);
}

GetNetsQueryNum <- function(){
  as.numeric(net.stats$Query);
}

# from to should be valid nodeIDs
GetShortestPaths <- function(from, to){
  current.net <- pheno.comps[[current.net.nm]];
  paths <- igraph::get.all.shortest.paths(current.net, from, to)$res;
  if(length(paths) == 0){
    return (paste("No connection between the two nodes!"));
  }

  path.vec <- vector(mode="character", length=length(paths));
  for(i in 1:length(paths)){
    path.inx <- paths[[i]];
    path.ids <- V(current.net)$name[path.inx];
    path.sybls <- path.ids;
    pids <- paste(path.ids, collapse="->");
    psbls <- paste(path.sybls, collapse="->");
    path.vec[i] <- paste(c(pids, psbls), collapse=";")
  }

  if(length(path.vec) > 50){
    path.vec <- path.vec[1:50];
  }

  all.paths <- paste(path.vec, collapse="||");
  return(all.paths);
}

# exclude nodes in current.net (networkview)
ExcludeNodes <- function(nodeids, filenm){
  nodes2rm <- strsplit(nodeids, ";", fixed=TRUE)[[1]];
  current.net <- pheno.comps[[current.net.nm]];
  current.net <- igraph::delete.vertices(current.net, nodes2rm);

  # need to remove all orphan nodes
  bad.vs<-V(current.net)$name[igraph::degree(current.net) == 0];
  current.net <- igraph::delete.vertices(current.net, bad.vs);

  # return all those nodes that are removed
  nds2rm <- paste(c(bad.vs, nodes2rm), collapse="||");

  # update topo measures
  node.btw <- as.numeric(igraph::betweenness(current.net));
  node.dgr <- as.numeric(igraph::degree(current.net));
  node.exp <- as.numeric(igraph::get.vertex.attribute(current.net, name="abundance", index = V(current.net)));
  nms <- V(current.net)$name;
  hit.inx <- match(nms, pheno.net$node.data[,1]);
  lbls <- pheno.net$node.data[hit.inx,2];

  nodes <- vector(mode="list");
  for(i in 1:length(nms)){
    nodes[[i]] <- list(
      id=nms[i],
      label=lbls[i],
      degree=node.dgr[i],
      between=node.btw[i],
      expr = node.exp[i]
    );
  }
  # now only save the node pos to json
  netData <- list(deletes=nds2rm, nodes=nodes);
  sink(filenm);
  cat(rjson::toJSON(netData));
  sink();

  pheno.comps[[current.net.nm]] <<- current.net;
  UpdateSubnetStats();

  # remember to forget the cached layout, and restart caching, as this is now different object (with the same name)
  #forget(PerformLayOut_mem);
  return(filenm);
}

# support walktrap, infomap and lab propagation
FindCommunities <- function(method="walktrap", use.weight=FALSE){

  # make sure this is the connected
  current.net <- pheno.comps[[current.net.nm]];
  g <- current.net;
  if(!is.connected(g)){
    g <- igraph::decompose.graph(current.net, min.vertices=2)[[1]];
  }
  total.size <- length(V(g));

  if(use.weight){ # this is only tested for walktrap, should work for other method
    # now need to compute weights for edges
    egs <- igraph::get.edges(g, E(g)); #node inx
    nodes <- V(g)$name;
    # conver to node id
    negs <- cbind(nodes[egs[,1]],nodes[egs[,2]]);

    # get min FC change
    base.wt <- min(abs(seed.expr))/10;

    # check if user only give a gene list without logFC or all same fake value
    if(length(unique(seed.expr)) == 1){
      seed.expr <- rep(1, nrow(negs));
      base.wt <- 0.1; # weight cannot be 0 in walktrap
    }

    wts <- matrix(base.wt, ncol=2, nrow = nrow(negs));
    for(i in 1:ncol(negs)){
      nd.ids <- negs[,i];
      hit.inx <- match(names(seed.expr), nd.ids);
      pos.inx <- hit.inx[!is.na(hit.inx)];
      wts[pos.inx,i]<- seed.expr[!is.na(hit.inx)]+0.1;
    }
    nwt <- apply(abs(wts), 1, function(x){mean(x)^2})
  }

  if(method == "walktrap"){
    fc <- igraph::walktrap.community(g);
  }else if(method == "infomap"){
    fc <- igraph::infomap.community(g);
  }else if(method == "labelprop"){
    fc <- igraph::label.propagation.community(g);
  }else{
    print(paste("Unknown method:", method));
    return ("NA||Unknown method!");
  }

  if(length(fc) == 0 || modularity(fc) == 0){
    return ("NA||No communities were detected!");
  }

  # only get communities
  communities <- igraph::communities(fc);
  community.vec <- vector(mode="character", length=length(communities));
  gene.community <- NULL;
  qnum.vec <- NULL;
  pval.vec <- NULL;
  rowcount <- 0;
  nms <- V(g)$name;
  hit.inx <- match(nms, pheno.net$node.data[,1]);
  sybls <- pheno.net$node.data[hit.inx,2];
  names(sybls) <- V(g)$name;
  for(i in 1:length(communities)){
    # update for igraph 1.0.1
    path.ids <- communities[[i]];
    psize <- length(path.ids);
    if(psize < 5){
      next; # ignore very small community
    }
    hits <- seed.proteins %in% path.ids;
    qnums <- sum(hits);
    if(qnums == 0){
      next; # ignor community containing no queries
    }

    rowcount <- rowcount + 1;
    pids <- paste(path.ids, collapse="->");
    #path.sybls <- V(g)$Label[path.inx];
    path.sybls <- sybls[path.ids];
    com.mat <- cbind(path.ids, path.sybls, rep(i, length(path.ids)));
    gene.community <- rbind(gene.community, com.mat);
    qnum.vec <- c(qnum.vec, qnums);

    # calculate p values (comparing in- out- degrees)
    #subgraph <- induced.subgraph(g, path.inx);
    subgraph <- igraph::induced.subgraph(g, path.ids);
    in.degrees <- igraph::degree(subgraph);
    #out.degrees <- igraph::degree(g, path.inx) - in.degrees;
    out.degrees <- igraph::degree(g, path.ids) - in.degrees;
    ppval <- wilcox.test(in.degrees, out.degrees)$p.value;
    ppval <- signif(ppval, 3);
    pval.vec <- c(pval.vec, ppval);

    # calculate community score
    community.vec[rowcount] <- paste(c(psize, qnums, ppval, pids), collapse=";");
  }

  ord.inx <- order(pval.vec, decreasing=F);
  community.vec <- community.vec[ord.inx];
  qnum.vec <- qnum.vec[ord.inx];
  ord.inx <- order(qnum.vec, decreasing=T);
  community.vec <- community.vec[ord.inx];

  all.communities <- paste(community.vec, collapse="||");
  colnames(gene.community) <- c("Id", "Label", "Module");
  fast.write.csv(gene.community, file="module_table.csv", row.names=F);
  return(all.communities);
}

community.significance.test <- function(graph, vs, ...) {
  subgraph <- igraph::induced.subgraph(graph, vs)
  in.degrees <- igraph::degree(subgraph)
  out.degrees <- igraph::degree(graph, vs) - in.degrees
  wilcox.test(in.degrees, out.degrees, ...)
}

###################################
# Adapted from netweavers package
###################
#'@import RColorBrewer
convertIgraph2JSON <- function(net.nm, filenm){
  library(igraph);
  net.nm<<-net.nm;
  filenm<<-filenm;

  table.nm <- pheno.net$table.nm;
  g <- pheno.comps[[net.nm]];
  # annotation
  nms <- V(g)$name;
  hit.inx <- match(nms, pheno.net$node.data[,1]);
  lbls <- pheno.net$node.data[hit.inx,2];
  gene.names <- pheno.net$node.data[hit.inx,3];

  if("Evidence" %in% colnames(pheno.net$node.data)){
    evidence.ids <- pheno.net$node.data[hit.inx,4];
  } else {
    evidence.ids <- rep("", length(gene.names));
  }

  # get edge data
  edge.mat <- igraph::get.edgelist(g);
  edge.evidence <- igraph::edge_attr(g, "Evidence");
  edge.coeff <- igraph::edge_attr(g, "Coefficient");
  edge.pval <- igraph::edge_attr(g, "Pval");
  edge.qval <- igraph::edge_attr(g, "Adj_Pval");
  if(table.nm=="dspc"){
    edge.sizes <- as.numeric(rescale2NewRange((-log10(edge.pval)), 0.5, 10));
    edge.sizes.qval <- as.numeric(rescale2NewRange((-log10(edge.qval)), 0.5, 10));
    edge.sizes.coeff <- as.numeric(rescale2NewRange(edge.coeff, 0.5, 10));
  }

  if(!is.null(edge.evidence)){
    edge.mat <- cbind(id=1:nrow(edge.mat), source=edge.mat[,1], target=edge.mat[,2], evidence=edge.evidence);
  } else if(!is.null(edge.coeff)){
    edge.mat <- cbind(id=1:nrow(edge.mat), source=edge.mat[,1], target=edge.mat[,2], coeff=edge.coeff, pval=edge.pval, qval=edge.qval, esize_pval=edge.sizes, esize_qval=edge.sizes.qval, esize_coeff=edge.sizes.coeff);
  }else{
    edge.mat <- cbind(id=1:nrow(edge.mat), source=edge.mat[,1], target=edge.mat[,2]);
  }

  # now get coords
  #pos.xy <- PerformLayOut_mem(net.nm, "Default");
  pos.xy <- PerformLayOut(net.nm, "Default");
  # get the note data
  node.btw <- as.numeric(igraph::betweenness(g));
  node.dgr <- as.numeric(igraph::degree(g));
  node.exp <- as.numeric(igraph::get.vertex.attribute(g, name="abundance", index = V(g)));

  # node size to degree values
  if(vcount(g)>500){
    min.size = 1;
  }else if(vcount(g)>200){
    min.size = 2;
  }else{
    min.size = 3;
  }
  node.sizes <- as.numeric(rescale2NewRange((log10(node.dgr))^2, min.size, 9));
  edge.sizes <- 1;
  centered = T;
  notcentered = F;
  coeff <- 0;

  if(table.nm != "dspc"){
  # update node color based on betweenness
  topo.val <- log10(node.btw+1);
  topo.colsb <- ComputeColorGradient(topo.val, "black", notcentered);
  topo.colsw <-  ComputeColorGradient(topo.val, "white", notcentered);

  # color based on expression
  bad.inx <- is.na(node.exp) | node.exp==0;
  if(!all(bad.inx)){
    exp.val <- node.exp;
    node.colsb.exp <- ComputeColorGradient(exp.val, "black", centered);
    node.colsw.exp <- ComputeColorGradient(exp.val, "white", centered);
    node.colsb.exp[bad.inx] <- "#d3d3d3";
    node.colsw.exp[bad.inx] <- "#c6c6c6";
    # node.colsw.exp[bad.inx] <- "#66CCFF";
  }else{
    node.colsb.exp <- rep("#d3d3d3",length(node.exp));
    node.colsw.exp <- rep("#c6c6c6",length(node.exp));
  }
}

  if(table.nm == "global"){
    # now update for bipartite network
    # setup shape (gene circle, other squares)
    # Circles for genes
    shapes <- rep("circle", length(nms));
    # Squares for phenotypes
    mir.inx <- nms %in% edge.mat[,"target"];
    shapes[mir.inx] <- "square";
    # Diamond for metabolites
    cmpds.node <- as.vector(sapply(nms, function(x) substr(x, 1, 1) == "C"))
    shapes[cmpds.node] <- "diamond"
    node.sizes[mir.inx] <- node.sizes[mir.inx] + 0.5;
    # update mir node color
    node.colsw.exp[mir.inx] <- topo.colsw[mir.inx] <- "#306EFF"; # dark blue
    node.colsb.exp[mir.inx] <- topo.colsb[mir.inx] <- "#98F5FF";
  } else if (table.nm == "dspc"){
    # Diamond for metabolites
    # can distinguish known and unknown metabolites using different shapes L.C.
    shapes <- rep("diamond", length(nms));
    topo.colsb <- rep("#98F5FF",length(nms));
    topo.colsw <- rep("#306EFF",length(nms)); # dark blue
    node.colsb.exp <- rep("#d3d3d3",length(node.exp));
    node.colsw.exp <- rep("#c6c6c6",length(node.exp));
  } else {
    # now update for bipartite network
    # setup shape (gene circle, other squares)
    shapes <- rep("circle", length(nms));
    if(pheno.net$db.type != 'ppi' && table.nm != "metabo_metabolites"){ # the other part miRNA or TF will be in square
      mir.inx <- nms %in% edge.mat[,"target"];
      shapes[mir.inx] <- "square";
      node.sizes[mir.inx] <- node.sizes[mir.inx] + 0.5;

      # update mir node color
      node.colsw.exp[mir.inx] <- topo.colsw[mir.inx] <- "#306EFF"; # dark blue
      node.colsb.exp[mir.inx] <- topo.colsb[mir.inx] <- "#98F5FF";
    }
  }

  # now create the json object
  nodes <- vector(mode="list");
  for(i in 1:length(node.sizes)){
    # TODO: avoid which here and just attach HMDB matched IDs to the list of Compound nodes
    hmdb.id <- mSet$dataSet$map.table[which(mSet$dataSet$map.table[,1] == nms[i]), 3]

    nodes[[i]] <- list(
      id=nms[i],
      idnb = i,
      hmdb=hmdb.id,
      label=lbls[i],
      evidence=evidence.ids[i],
      genename=gene.names[i],
      x = pos.xy[i,1],
      y = pos.xy[i,2],
      size=node.sizes[i],
      type=shapes[i],
      colorb=topo.colsb[i],
      colorw=topo.colsw[i],
      attributes=list(
        expr = node.exp[i],
        expcolb=node.colsb.exp[i],
        expcolw=node.colsw.exp[i],
        degree=node.dgr[i],
        between=node.btw[i])
    );
  }

  # save node table
  nd.tbl <- data.frame(Id=nms, Label=lbls, Degree=node.dgr, Betweenness=round(node.btw,2));
  # order
  ord.inx <- order(nd.tbl[,3], nd.tbl[,4], decreasing = TRUE)
  nd.tbl <- nd.tbl[ord.inx, ];
  fast.write.csv(nd.tbl, file="node_table.csv", row.names=FALSE);

  # covert to json
  netData <- list(nodes=nodes, edges=edge.mat);
  netData[["edges"]] <- lapply(seq(nrow(netData[["edges"]])), FUN = function(x) {netData[["edges"]][x,]})
  sink(filenm);
  cat(rjson::toJSON(netData));
  sink();
}

# also save to GraphML
ExportNetwork <- function(fileName){
  current.net <- pheno.comps[[current.net.nm]];
  igraph::write.graph(current.net, file=fileName, format="graphml");
}

ExtractModule<- function(nodeids){
  set.seed(8574);
  nodes <- strsplit(nodeids, ";", fixed=TRUE)[[1]];

  g <- pheno.comps[[current.net.nm]];
  # try to see if the nodes themselves are already connected
  hit.inx <- V(g)$name %in% nodes;
  gObj <- igraph::induced.subgraph(g, V(g)$name[hit.inx]);

  # now find connected components
  comps <- igraph::decompose.graph(gObj, min.vertices=1);

  if(length(comps) == 1){ # nodes are all connected
    g <- comps[[1]];
  }else{
    # extract modules
    paths.list <-list();
    sd.len <- length(nodes);
    for(pos in 1:sd.len){
      paths.list[[pos]] <- igraph::get.shortest.paths(g, nodes[pos], nodes[-(1:pos)])$vpath;
    }
    nds.inxs <- unique(unlist(paths.list));
    nodes2rm <- V(g)$name[-nds.inxs];
    g <- simplify(igraph::delete.vertices(g, nodes2rm));
  }
  nodeList <- igraph::get.data.frame(g, "vertices");
  if(nrow(nodeList) < 3){
    return ("NA");
  }

  module.count <- module.count + 1;
  module.nm <- paste("module", module.count, sep="");
  colnames(nodeList) <- c("Id", "Label");
  ndFileNm = paste(module.nm, "_node_list.csv", sep="");
  fast.write.csv(nodeList, file=ndFileNm, row.names=FALSE);

  edgeList <- igraph::get.data.frame(g, "edges");
  edgeList <- cbind(rownames(edgeList), edgeList);
  colnames(edgeList) <- c("Id", "Source", "Target");
  edgFileNm = paste(module.nm, "_edge_list.csv", sep="");
  fast.write.csv(edgeList, file=edgFileNm, row.names=FALSE);

  filenm <- paste(module.nm, ".json", sep="");

  # record the module
  pheno.comps[[module.nm]] <<- g;
  UpdateSubnetStats();

  module.count <<- module.count;

  convertIgraph2JSON(module.nm, filenm);
  return (filenm);
}

PerformLayOut <- function(net.nm, algo){
  library(igraph);
  g <- pheno.comps[[net.nm]];
  vc <- vcount(g);
  if(algo == "Default"){
    if(vc > 5000) {
      pos.xy <- layout_with_lgl(g);
    }else if(vc < 100){
      pos.xy <- layout_with_kk(g);
    }else{
      pos.xy <- layout_with_fr(g);
    }
  }else if(algo == "FrR"){
    pos.xy <- layout_with_fr(g, area=34*vc^2);
  }else if(algo == "circle"){
    pos.xy <- layout_in_circle(g);
  }else if(algo == "random"){
    pos.xy <- layout_randomly (g);
  }else if(algo == "lgl"){
    pos.xy <- layout_with_lgl(g);
  }else if(algo == "gopt"){
    pos.xy <- layout_with_graphopt(g)
  }
  pos.xy;
}

UpdateNetworkLayout <- function(algo, filenm, curr.nm="NA"){
  if(curr.nm != "NA"){
    current.net.nm <<- curr.nm;
  }
  current.net <- pheno.comps[[current.net.nm]];
  #pos.xy <- PerformLayOut_mem(current.net.nm, algo);
  pos.xy <- PerformLayOut(current.net.nm, algo);
  nms <- V(current.net)$name;
  nodes <- vector(mode="list");
  for(i in 1:length(nms)){
    nodes[[i]] <- list(
      id=nms[i],
      x=pos.xy[i,1],
      y=pos.xy[i,2]
    );
  }
  # now only save the node pos to json
  netData <- list(nodes=nodes);
  sink(filenm);
  cat(rjson::toJSON(netData));
  sink();
  return(filenm);
}


doID2LabelMapping <- function(entrez.vec){

  hit.inx <- match(entrez.vec, nodeListu[, "Id"]);
  symbols <- nodeListu[hit.inx, "Label"];

  # if not gene symbol, use id by itself
  na.inx <- is.na(symbols);
  symbols[na.inx] <- entrez.vec[na.inx];
  return(symbols);
}


# re-arrange one vector elements according to another vector values
# usually src is character vector to be arranged
# target is numberic vector of same length
sync2vecs <- function(src.vec, tgt.vec){
  if(length(src.vec) != length(tgt.vec)){
    print("must be of the same length!");
    return();
  }
  ord.inx <- match(rank(tgt.vec, ties.method="random"), 1:length(tgt.vec));
  src.vec[ord.inx];
}

# for a given graph, obtain the smallest subgraphs that contain
# all the seed nodes. This is acheived by iteratively remove
# the marginal nodes (degree = 1) that are not in the seeds
GetMinConnectedGraphs <- function(mSetObj=NA, max.len = 200){
  mSetObj <- .get.mSet(mSetObj);
  # need to test
  set.seed(8574);
  # first get shortest paths for all pair-wise seeds
  my.seeds <- seed.graph;

  # remove seeds not in the network
  keep.inx <- my.seeds %in% V(overall.graph)$name;
  my.seeds <- my.seeds[keep.inx]; 
  sd.len <- length(my.seeds);
  paths.list <-list();

  # first trim overall.graph to remove no-seed nodes of degree 1
  dgrs <- igraph::degree(overall.graph);
  keep.inx <- dgrs > 1 | (names(dgrs) %in% my.seeds);
  nodes2rm <- V(overall.graph)$name[!keep.inx];
  overall.graph <-  simplify(delete.vertices(overall.graph, nodes2rm));

  # need to restrict the operation b/c get.shortest.paths is very time consuming
  # for top max.len highest degrees
  if(sd.len > max.len){
    hit.inx <- names(dgrs) %in% my.seeds;
    sd.dgrs <- dgrs[hit.inx];
    sd.dgrs <- rev(sort(sd.dgrs));
    # need to synchronize all (seed.proteins) and top seeds (my.seeds)
    seed.proteins <- names(sd.dgrs);
    if(max.len>table(hit.inx)[["TRUE"]]){
      sd.len <-  table(hit.inx)[["TRUE"]];
    }else{
      sd.len <-  max.len;
    }
    my.seeds <- seed.proteins[1:sd.len];
    msg <- paste("The minimum connected network was computed using the top", sd.len, "seed proteins in the network based on their degrees.");
  }else{
    msg <- paste("The minimum connected network was computed using all seed proteins in the network.");
  }
  AddMsg(msg);

  # now calculate the shortest paths for
  # each seed vs. all other seeds (note, to remove pairs already calculated previously)
  for(pos in 1:sd.len){
    paths.list[[pos]] <- get.shortest.paths(overall.graph, my.seeds[pos], seed.proteins[-(1:pos)])$vpath;
  }
  nds.inxs <- unique(unlist(paths.list));
  nodes2rm <- V(overall.graph)$name[-nds.inxs];
  g <- simplify(delete.vertices(overall.graph, nodes2rm));

  nodeList <- get.data.frame(g, "vertices");
  colnames(nodeList) <- c("Id", "Label");
  fast.write.csv(nodeList, file="orig_node_list.csv", row.names=F);

  edgeList <- get.data.frame(g, "edges");
  edgeList <- cbind(rownames(edgeList), edgeList);
  colnames(edgeList) <- c("Id", "Source", "Target");
  fast.write.csv(edgeList, file="orig_edge_list.csv", row.names=F);

  path.list <- NULL;
  substats <- DecomposeGraph(g);
  net.stats<<-net.stats

  if(.on.public.web){
    mSetObj <- .get.mSet(mSetObj);
    if(!is.null(substats)){
      overall.graph <<- overall.graph;
      return(c(length(seed.graph),length(seed.proteins), vcount(overall.graph), ecount(overall.graph), length(pheno.comps), substats));
    }else{
      return(0);
    }
  }else{
    return(.set.mSet(mSetObj));
  }
}

FilterNetByCor <- function(min.pval, min.qval, neg.coeff1, neg.coeff2, pos.coeff1, pos.coeff2){
  mSetObj <- .get.mSet(mSetObj);
  
  edge.list <- pheno.net$edge.data;
  # filter by correlation coefficient only
  edge.list.filter.neg <- edge.list[which(edge.list$Coefficient >= neg.coeff1 & edge.list$Coefficient < neg.coeff2),];
  edge.list.filter.pos <- edge.list[which(edge.list$Coefficient >= pos.coeff1 & edge.list$Coefficient < pos.coeff2),];
  edge.list.filter <- rbind(edge.list.filter.neg, edge.list.filter.pos);
  # filter by both correlation coefficient and p values
  # also apply to filter by p values only b/c correlation coefficient were set to -1, 0, 0, 1 in java 
  if(min.pval > 0){
    edge.list.filter.neg <- edge.list[which(edge.list$Pval <= min.pval & edge.list$Coefficient >= neg.coeff1 & edge.list$Coefficient < neg.coeff2),];
    edge.list.filter.pos <- edge.list[which(edge.list$Pval <= min.pval & edge.list$Coefficient >= pos.coeff1 & edge.list$Coefficient < pos.coeff2),];
    edge.list.filter <- rbind(edge.list.filter.neg, edge.list.filter.pos);
  }
  if(min.qval > 0){
    edge.list.filter.neg <- edge.list[which(edge.list$Adj_Pval <= min.qval & edge.list$Coefficient >= neg.coeff1 & edge.list$Coefficient < neg.coeff2),];
    edge.list.filter.pos <- edge.list[which(edge.list$Adj_Pval <= min.qval & edge.list$Coefficient >= pos.coeff1 & edge.list$Coefficient < pos.coeff2),];
    edge.list.filter <- rbind(edge.list.filter.neg, edge.list.filter.pos);
  }
  overall.graph <-simplify(graph_from_data_frame(edge.list.filter, directed=FALSE, vertices=NULL), edge.attr.comb="first");
  msg <- paste("A total of", nrow(edge.list)-nrow(edge.list.filter) , "edges was reduced.");
  AddMsg(msg);

  substats <- DecomposeGraph(overall.graph);
  if(.on.public.web){
    mSetObj <- .get.mSet(mSetObj);
    if(!is.null(substats)){
      overall.graph <<- overall.graph;
      return(c(length(seed.proteins),length(seed.proteins), vcount(overall.graph), ecount(overall.graph), length(pheno.comps), substats));
    }else{
      return(0);
    }
  }else{
    return(.set.mSet(mSetObj));
  }
}

FilterBipartiNet <- function(mSetObj=NA, nd.type, min.dgr, min.btw){

  mSetObj <- .get.mSet(mSetObj);
  all.nms <- V(overall.graph)$name;
  edge.mat <- get.edgelist(overall.graph);
  dgrs <- igraph::degree(overall.graph);
  nodes2rm.dgr <- nodes2rm.btw <- NULL;

  if(nd.type == "gene"){
    hit.inx <- all.nms %in% edge.mat[,1];
  }else if(nd.type=="other"){
    hit.inx <- all.nms %in% edge.mat[,2];
  }else{ # all
    hit.inx <- rep(TRUE, length(all.nms));
  }

  if(min.dgr > 0){
    rm.inx <- dgrs <= min.dgr & hit.inx;
    nodes2rm.dgr <- V(overall.graph)$name[rm.inx];
  }
  if(min.btw > 0){
    btws <- betweenness(overall.graph);
    rm.inx <- btws <= min.btw & hit.inx;
    nodes2rm.btw <- V(overall.graph)$name[rm.inx];
  }

  nodes2rm <- unique(c(nodes2rm.dgr, nodes2rm.btw));
  overall.graph <- simplify(delete.vertices(overall.graph, nodes2rm), edge.attr.comb=list("first"));
  # the simplify() function removes the edge attributes by default
  # added edge.attr.comb=list("first") to always chooses the first attribute value
  AddMsg(paste("A total of", length(nodes2rm) , "was reduced."));
  substats <- DecomposeGraph(overall.graph);
  if(.on.public.web){
    mSetObj <- .get.mSet(mSetObj);
    if(!is.null(substats)){
      overall.graph <<- overall.graph;
      return(c(length(seed.graph),length(seed.proteins), vcount(overall.graph), ecount(overall.graph), length(pheno.comps), substats));
    }else{
      return(0);
    }
  }else{
    return(.set.mSet(mSetObj));
  }
}

GetMaxRawPVal<-function(mSetObj=NA){
  edge.attr <- edge_attr(overall.graph);
  res <- round(max(edge.attr$Pval), digits = 6);
  return(res)
}

GetMinNegCoeff<-function(mSetObj=NA){
  edge.attr <- edge_attr(overall.graph);
  coeff <- edge.attr$Coefficient;
  neg.coeff <- coeff[coeff<0];
  if(length(neg.coeff) == 0){ # when there is no negative coefficnets
    res <- 0;
  }else {
    res <- round(min(neg.coeff), digits = 6);
  }
  return(res)
}

GetMaxNegCoeff<-function(mSetObj=NA){
  edge.attr <- edge_attr(overall.graph);
  coeff <- edge.attr$Coefficient;
  neg.coeff <- coeff[coeff<0];
  if(length(neg.coeff) == 0){ # when there is no negative coefficnets
    res <- 0;
  }else {
    res <- round(max(neg.coeff), digits = 6);
  }
  return(res)
}

GetMinPosCoeff<-function(mSetObj=NA){
  edge.attr <- edge_attr(overall.graph);
  coeff <- edge.attr$Coefficient;
  pos.coeff <- coeff[coeff>0];
  if(length(pos.coeff) == 0){ # when there is no positive coefficnets
    res <- 0;
  }else {
    res <- round(min(pos.coeff), digits = 6);
  }
  return(res)
}

GetMaxPosCoeff<-function(mSetObj=NA){
  edge.attr <- edge_attr(overall.graph);
  coeff <- edge.attr$Coefficient;
  pos.coeff <- coeff[coeff>0];
  if(length(pos.coeff) == 0){ # when there is no positive coefficnets
    res <- 0;
  }else {
    res <- round(max(pos.coeff), digits = 6);
  }
  return(res)
}
