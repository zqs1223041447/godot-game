"""Read-only mesh collision geometry helpers adapted from the frozen v108 calculation. No file IO."""
import numpy as np
from scipy.spatial import ConvexHull
from osgeo import ogr
ogr.UseExceptions()

def clip(poly,axis,value,keep_above):
 if len(poly)==0:return []
 out=[]
 for i,a in enumerate(poly):
  b=poly[(i+1)%len(poly)]; da=(a[axis]-value)*(1 if keep_above else -1); db=(b[axis]-value)*(1 if keep_above else -1)
  ina=da>=-1e-12; inb=db>=-1e-12
  if ina:out.append(a)
  if ina!=inb:
   t=(value-a[axis])/(b[axis]-a[axis]); out.append(a+t*(b-a))
 return out

def polygon(points):
 ring=ogr.Geometry(ogr.wkbLinearRing)
 for x,y in points:ring.AddPoint_2D(float(x),float(y))
 ring.CloseRings();p=ogr.Geometry(ogr.wkbPolygon);p.AddGeometry(ring);return p

def line(points):
 g=ogr.Geometry(ogr.wkbLineString)
 for x,y in points:g.AddPoint_2D(float(x),float(y))
 return g

def polys(g):
 if g is None or g.IsEmpty():return []
 if ogr.GT_Flatten(g.GetGeometryType())==ogr.wkbPolygon:return [g]
 out=[]
 for i in range(g.GetGeometryCount()):out.extend(polys(g.GetGeometryRef(i)))
 return out

def collection_union(gs):
 coll=ogr.Geometry(ogr.wkbGeometryCollection)
 for g in gs:
  if g is not None and not g.IsEmpty():coll.AddGeometry(g)
 return coll.UnaryUnion()

def boundary_section(v,t,z):
 """Closed section caps, derived from actual triangles, snap 0.1 micrometre seams."""
 segs=ogr.Geometry(ogr.wkbMultiLineString);faces=[];tri=v[t]
 ids=np.where((tri[:,:,2].min(axis=1)<=z+1e-10)&(tri[:,:,2].max(axis=1)>=z-1e-10))[0]
 for k in ids:
  q=tri[k]; pts=[]
  if np.max(abs(q[:,2]-z))<1e-10:
   pg=polygon(q[:,:2]);
   if pg.GetArea()>1e-12:faces.append(pg)
   continue
  for j in range(3):
   a=q[j];b=q[(j+1)%3]
   if abs(a[2]-z)<1e-10:pts.append(a[:2])
   if (a[2]-z)*(b[2]-z)<0:pts.append((a+(z-a[2])/(b[2]-a[2])*(b-a))[:2])
  unique=np.unique(np.round(pts,7),axis=0) if len(pts) else []
  if len(unique)==2 and np.linalg.norm(unique[0]-unique[1])>1e-9:segs.AddGeometry(line(unique))
 if segs.GetGeometryCount():
  noded=segs.UnaryUnion(); caps=noded.Polygonize()
  faces.extend(polys(caps))
 return collection_union(faces),segs.GetGeometryCount()

def slab_footprint(v,t,lo,hi,rock=False,need_raw=True):
 tri=v[t]; ids=np.where((tri[:,:,2].max(axis=1)>=lo)&(tri[:,:,2].min(axis=1)<=hi))[0]
 surface=[];points=[]
 for k in ids:
  q=clip(list(tri[k]),2,lo,True);q=clip(q,2,hi,False)
  if len(q)<3:continue
  xy=np.asarray(q)[:,:2];points.extend(xy)
  if need_raw:
   pg=polygon(xy)
   if pg.GetArea()>1e-12:surface.append(pg)
 caps=[];segments=[]
 for z in [lo,hi]:
  cap,n=boundary_section(v,t,z);caps.append(cap);segments.append(n)
 raw=collection_union(surface+caps) if need_raw else None
 hull=polygon(np.asarray(points)[ConvexHull(np.asarray(points)).vertices]) if points else ogr.Geometry(ogr.wkbPolygon)
 # Hulls on scanned rocks intentionally fill concave niches / scan openings.
 base=hull if rock else raw
 return base,raw,{'triangles_intersecting_body_band':len(ids),'cap_segment_counts_lower_upper':segments,'surface_projection_polygon_count':len(surface),'raw_union_area_m2':raw.GetArea() if raw else None,'convex_hull_area_m2':hull.GetArea()}

