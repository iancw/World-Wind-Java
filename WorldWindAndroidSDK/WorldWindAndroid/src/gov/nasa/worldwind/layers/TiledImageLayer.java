/*
 * Copyright (C) 2012 United States Government as represented by the Administrator of the
 * National Aeronautics and Space Administration.
 * All Rights Reserved.
 */
package gov.nasa.worldwind.layers;

import gov.nasa.worldwind.*;
import gov.nasa.worldwind.avlist.*;
import gov.nasa.worldwind.cache.*;
import gov.nasa.worldwind.geom.*;
import gov.nasa.worldwind.render.*;
import gov.nasa.worldwind.util.*;
import org.w3c.dom.*;

import javax.xml.xpath.XPath;
import java.util.*;
import java.util.concurrent.PriorityBlockingQueue;

/**
 * @author dcollins
 * @version $Id$
 */
// TODO: apply layer opacity during rendering
public abstract class TiledImageLayer extends AbstractLayer implements Tile.TileFactory
{
    protected LevelSet levels;
    protected double detailHintOrigin = 2.8; // the default detail hint origin
    protected double detailHint;
    protected List<Tile> topLevelTiles = new ArrayList<Tile>();
    protected GpuTextureFactory textureFactory;
    protected String tileCountName;

    // Stuff computed each frame
    protected List<GpuTextureTile> currentTiles = new ArrayList<GpuTextureTile>();
    protected GpuTextureTile currentAncestorTile;
    protected PriorityBlockingQueue<Runnable> requestQ = new PriorityBlockingQueue<Runnable>(200);

    abstract protected void requestTile(DrawContext dc, GpuTextureTile tile);

    public TiledImageLayer(LevelSet levelSet)
    {
        if (levelSet == null)
        {
            String message = Logging.getMessage("nullValue.LevelSetIsNull");
            Logging.error(message);
            throw new IllegalArgumentException(message);
        }

        this.levels = new LevelSet(levelSet); // the caller's levelSet may change internally, so we copy it.
        this.setValue(AVKey.SECTOR, this.levels.getSector());

        this.setPickEnabled(false); // textures are assumed to be terrain unless specifically indicated otherwise.
        this.tileCountName = this.getName() + " Tiles";

        this.textureFactory = this.createTextureFactory();
    }

    @Override
    public Object setValue(String key, Object value)
    {
        // Offer it to the level set
        if (this.getLevels() != null)
            this.getLevels().setValue(key, value);

        return super.setValue(key, value);
    }

    @Override
    public Object getValue(String key)
    {
        Object value = super.getValue(key);

        return value != null ? value : this.getLevels().getValue(key); // see if the level set has it
    }

    /**
     * Indicates the layer's detail hint, which is described in {@link #setDetailHint(double)}.
     *
     * @return the detail hint
     *
     * @see #setDetailHint(double)
     */
    @SuppressWarnings("UnusedDeclaration")
    public double getDetailHint()
    {
        return this.detailHint;
    }

    /**
     * Modifies the default relationship of image resolution to screen resolution as the viewing altitude changes.
     * Values greater than 0 cause imagery to appear at higher resolution at greater altitudes than normal, but at an
     * increased performance cost. Values less than 0 decrease the default resolution at any given altitude. The default
     * value is 0. Values typically range between -0.5 and 0.5.
     * <p/>
     * Note: The resolution-to-height relationship is defined by a scale factor that specifies the approximate size of
     * discernible lengths in the image relative to eye distance. The scale is specified as a power of 10. A value of 3,
     * for example, specifies that 1 meter on the surface should be distinguishable from an altitude of 10^3 meters
     * (1000 meters). The default scale is 1/10^2.8, (1 over 10 raised to the power 2.8). The detail hint specifies
     * deviations from that default. A detail hint of 0.2 specifies a scale of 1/1000, i.e., 1/10^(2.8 + .2) = 1/10^3.
     * Scales much larger than 3 typically cause the applied resolution to be higher than discernible for the altitude.
     * Such scales significantly decrease performance.
     *
     * @param detailHint the degree to modify the default relationship of image resolution to screen resolution with
     *                   changing view altitudes. Values greater than 1 increase the resolution. Values less than zero
     *                   decrease the resolution. The default value is 0.
     */
    public void setDetailHint(double detailHint)
    {
        this.detailHint = detailHint;
    }

    protected LevelSet getLevels()
    {
        return levels;
    }

    /**
     * Specifies the time of the layer's most recent dataset update, beyond which cached data is invalid. If greater
     * than zero, the layer ignores and eliminates any in-memory or on-disk cached data older than the time specified,
     * and requests new information from the data source. If zero, the default, the layer applies any expiry times
     * associated with its individual levels, but only for on-disk cached data. In-memory cached data is expired only
     * when the expiry time is specified with this method and is greater than zero. This method also overwrites the
     * expiry times of the layer's individual levels if the value specified to the method is greater than zero.
     *
     * @param expiryTime the expiry time of any cached data, expressed as a number of milliseconds beyond the epoch. The
     *                   default expiry time is zero.
     *
     * @see System#currentTimeMillis() for a description of milliseconds beyond the epoch.
     */
    @Override
    public void setExpiryTime(long expiryTime) // Override this method to use intrinsic level-specific expiry times
    {
        super.setExpiryTime(expiryTime);

        if (expiryTime > 0)
            this.levels.setExpiryTime(expiryTime); // remove this in sub-class to use level-specific expiry times
    }

    protected GpuTextureFactory createTextureFactory()
    {
        return (GpuTextureFactory) WorldWind.createConfigurationComponent(AVKey.GPU_TEXTURE_FACTORY);
    }

    protected void checkTextureExpiration(DrawContext dc, List<GpuTextureTile> tiles)
    {
        for (GpuTextureTile tile : tiles)
        {
            if (tile.isTextureExpired())
                this.requestTile(dc, tile);
        }
    }

    protected void sendRequests()
    {
        Runnable task = this.requestQ.poll();
        while (task != null)
        {
            if (!WorldWind.getTaskService().isFull())
            {
                WorldWind.getTaskService().runTask(task);
            }
            task = this.requestQ.poll();
        }
    }

    /**
     * {@inheritDoc}
     * <p/>
     * Overridden to return <code>false</code> when this layer's LevelSet is entirely outside of the current visible
     * sector. This provides an effective way to cull the entire layer before it performs any unnecessary work.
     */
    @Override
    public boolean isLayerInView(DrawContext dc)
    {
        return dc.getVisibleSector() == null || dc.getVisibleSector().intersects(this.levels.getSector());
    }

    // ============== Rendering ======================= //
    // ============== Rendering ======================= //
    // ============== Rendering ======================= //

    @Override
    protected void doRender(DrawContext dc)
    {
        if (dc.getSurfaceGeometry() == null || dc.getSurfaceGeometry().size() < 1)
            return;

        this.assembleTiles(dc);

        if (!this.currentTiles.isEmpty())
        {
            // TODO: apply opacity and transparent texture support

            dc.addPerFrameStatistic(PerformanceStatistic.IMAGE_TILE_COUNT, this.tileCountName,
                this.currentTiles.size());
            dc.getSurfaceTileRenderer().renderTiles(dc, this.currentTiles);

            // Check texture expiration. Memory-cached textures are checked for expiration only when an explicit,
            // non-zero expiry time has been set for the layer. If none has been set, the expiry times of the layer's
            // individual levels are used, but only for images in the local file cache, not textures in memory. This is
            // to avoid incurring the overhead of checking expiration of in-memory textures, a very rarely used feature.
            if (this.getExpiryTime() > 0 && this.getExpiryTime() < System.currentTimeMillis())
                this.checkTextureExpiration(dc, this.currentTiles);

            this.currentTiles.clear();
        }

        this.sendRequests();
        this.requestQ.clear();

        // TODO: clear fallback tiles
    }

    public GpuTextureTile createTile(Sector sector, Level level, int row, int column)
    {
        if (sector == null)
        {
            String msg = Logging.getMessage("nullValue.SectorIsNull");
            Logging.error(msg);
            throw new IllegalArgumentException(msg);
        }

        if (level == null)
        {
            String msg = Logging.getMessage("nullValue.LevelIsNull");
            Logging.error(msg);
            throw new IllegalArgumentException(msg);
        }

        if (row < 0)
        {
            String msg = Logging.getMessage("generic.RowIndexOutOfRange", row);
            Logging.error(msg);
            throw new IllegalArgumentException(msg);
        }

        if (column < 0)
        {
            String msg = Logging.getMessage("generic.ColumnIndexOutOfRange", column);
            Logging.error(msg);
            throw new IllegalArgumentException(msg);
        }

        return new GpuTextureTile(sector, level, row, column, this.getTextureTileCache(), this.textureFactory);
    }

    // ============== Tile Assembly ======================= //
    // ============== Tile Assembly ======================= //
    // ============== Tile Assembly ======================= //

    protected void assembleTiles(DrawContext dc)
    {
        this.currentTiles.clear();

        if (this.topLevelTiles.isEmpty())
            this.createTopLevelTiles();

        for (Tile tile : this.topLevelTiles)
        {
            this.updateTileExtent(dc, (GpuTextureTile) tile);
            this.currentAncestorTile = null;

            if (this.isTileVisible(dc, (GpuTextureTile) tile))
                this.addTileOrDescendants(dc, (GpuTextureTile) tile);
        }
    }

    protected void createTopLevelTiles()
    {
        if (this.levels.getFirstLevel() == null)
        {
            Logging.warning(Logging.getMessage("generic.FirstLevelIsNull"));
            return;
        }

        this.topLevelTiles.clear();
        Tile.createTilesForLevel(this.levels.getFirstLevel(), this.levels.getSector(), this, this.topLevelTiles);
    }

    protected void addTileOrDescendants(DrawContext dc, GpuTextureTile tile)
    {
        this.updateTileExtent(dc, tile);

        if (this.meetsRenderCriteria(dc, tile))
        {
            this.addTile(dc, tile);
            return;
        }

        // The incoming tile does not meet the rendering criteria, so it must be subdivided and those subdivisions
        // tested against the criteria.

        // All tiles that meet the selection criteria are drawn, but some of those tiles will not have textures
        // associated with them because their texture isn't loaded yet. In this case the tiles use the texture of the
        // closest ancestor that has a texture loaded. The ancestor is called the currentAncestorTile. A texture
        // transform is applied during rendering to align the sector's texture coordinates with the appropriate region
        // of the ancestor's texture.

        MemoryCache cache = this.getTextureTileCache();
        GpuTextureTile ancestorTile = null;

        try
        {
            if (tile.isTextureInMemory(dc.getGpuResourceCache()) || tile.getLevelNumber() == 0)
            {
                ancestorTile = this.currentAncestorTile;
                this.currentAncestorTile = tile;
            }

            Tile[] subTiles = tile.subdivide(this.levels.getLevel(tile.getLevelNumber() + 1), cache, this);
            for (Tile child : subTiles)
            {
                // Put all sub-tiles in the terrain tile cache to avoid repeatedly allocating them each frame. Top level
                // tiles are not cached because they are held in the topLevelTiles list. Sub tiles are placed in the
                // cache here, and updated when their terrain geometry changes.
                if (!cache.contains(child.getTileKey()))
                    cache.put(child.getTileKey(), child);

                // Add descendant tiles that intersect the LevelSet's sector and are visible. If half or more of this
                // tile (in either latitude or longitude) extends beyond the LevelSet's sector, then two or three of its
                // children will be entirely outside the LevelSet's sector.
                if (this.levels.getSector().intersects(child.getSector())
                    && this.isTileVisible(dc, (GpuTextureTile) child))
                {
                    this.addTileOrDescendants(dc, (GpuTextureTile) child);
                }
            }
        }
        finally
        {
            if (ancestorTile != null)
                this.currentAncestorTile = ancestorTile;
        }
    }

    protected void addTile(DrawContext dc, GpuTextureTile tile)
    {
        tile.setFallbackTile(null);

        // If this tile's level is empty, just ignore it. When the view moves closer to the tile it is subdivided and
        // an non-empty child level is eventually added.
        if (tile.getLevel().isEmpty())
            return;

        // If the tile's texture is in memory, add it to the list of current tiles and return.
        if (tile.isTextureInMemory(dc.getGpuResourceCache()))
        {
            this.currentTiles.add(tile);
            return;
        }

        // The tile's texture is not in memory. Issue a request for the texture data if the tile is not already marked
        // as an absent resource. We ignore absent resources to avoid flooding the system with requests for resources
        // that are never resolved.
        if (!this.levels.isResourceAbsent(tile))
            this.requestTile(dc, tile);

        if (this.currentAncestorTile != null)
        {
            // If the current ancestor tile's texture is in memory, then use it as this tile's fallback tile and add
            // this tile to the list of current tiles. Otherwise, we check if the ancestor tile is a level zero tile and
            // if so issue a request to load it into memory. This is critical to correctly handling the case when an
            // application is resumed with the view close to the globe. In that case, the level zero tiles are never
            // initially loaded and the tile that meets the render criteria may have no data. By issuing a request for
            // level zero ancestor tiles, we ensure that something displays when the application resumes.

            if (this.currentAncestorTile.isTextureInMemory(dc.getGpuResourceCache()))
            {
                tile.setFallbackTile(this.currentAncestorTile);
                this.currentTiles.add(tile);
            }
            else if (this.currentAncestorTile.getLevelNumber() == 0)
            {
                if (!this.levels.isResourceAbsent(this.currentAncestorTile))
                    this.requestTile(dc, this.currentAncestorTile);
            }
        }
    }

    protected boolean isTileVisible(DrawContext dc, GpuTextureTile tile)
    {
        // TODO: compute extent every frame or periodically update
        if (tile.getExtent() == null)
            tile.setExtent(this.computeTileExtent(dc, tile));

        Sector visibleSector = dc.getVisibleSector();
        Extent extent = tile.getExtent();

        return (visibleSector == null || visibleSector.intersects(tile.getSector()))
            && (extent == null || dc.getView().getFrustumInModelCoordinates().intersects(extent));
    }

    protected boolean meetsRenderCriteria(DrawContext dc, GpuTextureTile tile)
    {
        return this.levels.isFinalLevel(tile.getLevelNumber()) || !this.needToSubdivide(dc, tile);
    }

    protected boolean needToSubdivide(DrawContext dc, GpuTextureTile tile)
    {
        return tile.mustSubdivide(dc, this.detailHintOrigin + this.detailHint);
    }

    protected void updateTileExtent(DrawContext dc, GpuTextureTile tile)
    {
        // TODO: regenerate the tile extent and reference points whenever the underlying elevation model changes.
        // TODO: regenerate the tile extent and reference points whenever the vertical exaggeration changes.

        if (tile.getExtent() == null)
        {
            tile.setExtent(this.computeTileExtent(dc, tile));
        }

        // Update the tile's reference points.
        Vec4[] points = tile.getReferencePoints();
        if (points == null)
        {
            points = new Vec4[] {new Vec4(), new Vec4(), new Vec4(), new Vec4(), new Vec4()};
            tile.getSector().computeCornerPoints(dc.getGlobe(), dc.getVerticalExaggeration(), points);
            tile.getSector().computeCentroidPoint(dc.getGlobe(), dc.getVerticalExaggeration(), points[4]);
            tile.setReferencePoints(points);
        }
    }

    protected Extent computeTileExtent(DrawContext dc, GpuTextureTile tile)
    {
        return Sector.computeBoundingBox(dc.getGlobe(), dc.getVerticalExaggeration(), tile.getSector());
    }

    /**
     * Returns the memory cache used to cache texture tiles, initializing the cache if it doesn't yet exist.
     *
     * @return the memory cache associated with texture tiles.
     */
    protected MemoryCache getTextureTileCache()
    {
        if (!WorldWind.getMemoryCacheSet().contains(GpuTextureTile.class.getName()))
        {
            long size = Configuration.getLongValue(AVKey.GPU_TEXTURE_TILE_CACHE_SIZE);
            MemoryCache cache = new BasicMemoryCache((long) (0.8 * size), size);
            cache.setName("Texture Tiles");
            WorldWind.getMemoryCacheSet().put(GpuTextureTile.class.getName(), cache);
        }

        return WorldWind.getMemoryCacheSet().get(GpuTextureTile.class.getName());
    }

    //**************************************************************//
    //********************  Configuration  *************************//
    //**************************************************************//

    /**
     * Parses TiledImageLayer configuration parameters from the specified DOM document. This writes output as key-value
     * pairs to params. If a parameter from the XML document already exists in params, that parameter is ignored.
     * Supported key and parameter names are: <table> <tr><th>Parameter</th><th>Element Path</th><th>Type</th></tr>
     * <tr><td>{@link AVKey#SERVICE_NAME}</td><td>Service/@serviceName</td><td>String</td></tr> <tr><td>{@link
     * AVKey#IMAGE_FORMAT}</td><td>ImageFormat</td><td>String</td></tr> <tr><td>{@link
     * AVKey#AVAILABLE_IMAGE_FORMATS}</td><td>AvailableImageFormats/ImageFormat</td><td>String array</td></tr>
     * <tr><td>{@link
     * AVKey#URL_CONNECT_TIMEOUT}</td><td>RetrievalTimeouts/ConnectTimeout/Time</td><td>Integer milliseconds</td></tr>
     * <tr><td>{@link AVKey#URL_READ_TIMEOUT}</td><td>RetrievalTimeouts/ReadTimeout/Time</td><td>Integer
     * milliseconds</td></tr> <tr><td>{@link AVKey#RETRIEVAL_QUEUE_STALE_REQUEST_LIMIT}</td>
     * <td>RetrievalTimeouts/StaleRequestLimit/Time</td><td>Integer milliseconds</td></tr> </table> This also parses
     * common layer and LevelSet configuration parameters by invoking {@link gov.nasa.worldwind.layers.AbstractLayer#getLayerConfigParams(org.w3c.dom.Element,
     * gov.nasa.worldwind.avlist.AVList)} and {@link gov.nasa.worldwind.util.DataConfigurationUtils#getLevelSetConfigParams(org.w3c.dom.Element,
     * gov.nasa.worldwind.avlist.AVList)}.
     *
     * @param domElement the XML document root to parse for TiledImageLayer configuration parameters.
     * @param params     the output key-value pairs which receive the TiledImageLayer configuration parameters. A null
     *                   reference is permitted.
     *
     * @return a reference to params, or a new AVList if params is null.
     *
     * @throws IllegalArgumentException if the document is null.
     */
    public static AVList getTiledImageLayerConfigParams(Element domElement, AVList params)
    {
        if (domElement == null)
        {
            String message = Logging.getMessage("nullValue.DocumentIsNull");
            Logging.error(message);
            throw new IllegalArgumentException(message);
        }

        if (params == null)
            params = new AVListImpl();

        XPath xpath = WWXML.makeXPath();

        // Common layer properties.
        AbstractLayer.getLayerConfigParams(domElement, params);

        // LevelSet properties.
        DataConfigurationUtils.getLevelSetConfigParams(domElement, params);

        // Service properties.
        WWXML.checkAndSetStringParam(domElement, params, AVKey.SERVICE_NAME, "Service/@serviceName", xpath);
        WWXML.checkAndSetBooleanParam(domElement, params, AVKey.RETRIEVE_PROPERTIES_FROM_SERVICE,
            "RetrievePropertiesFromService", xpath);

        // Image format properties.
        WWXML.checkAndSetStringParam(domElement, params, AVKey.IMAGE_FORMAT, "ImageFormat", xpath);
        WWXML.checkAndSetUniqueStringsParam(domElement, params, AVKey.AVAILABLE_IMAGE_FORMATS,
            "AvailableImageFormats/ImageFormat", xpath);

        // Optional behavior properties.
        WWXML.checkAndSetDoubleParam(domElement, params, AVKey.DETAIL_HINT, "DetailHint", xpath);
        //WWXML.checkAndSetColorArrayParam(domElement, params, AVKey.TRANSPARENCY_COLORS, "TransparencyColors/Color",
        //    xpath);

        // Retrieval properties. Convert the Long time values to Integers, because BasicTiledImageLayer is expecting
        // Integer values.
        WWXML.checkAndSetTimeParamAsInteger(domElement, params, AVKey.URL_CONNECT_TIMEOUT,
            "RetrievalTimeouts/ConnectTimeout/Time", xpath);
        WWXML.checkAndSetTimeParamAsInteger(domElement, params, AVKey.URL_READ_TIMEOUT,
            "RetrievalTimeouts/ReadTimeout/Time", xpath);
        WWXML.checkAndSetTimeParamAsInteger(domElement, params, AVKey.RETRIEVAL_QUEUE_STALE_REQUEST_LIMIT,
            "RetrievalTimeouts/StaleRequestLimit/Time", xpath);

        return params;
    }

    // ============== Bulk Download ======================= //
    // ============== Bulk Download ======================= //
    // ============== Bulk Download ======================= //


    public int computeLevelForResolution(Sector sector, double resolution)
    {
        if (sector == null)
        {
            String message = Logging.getMessage("nullValue.SectorIsNull");
            Logging.error(message);
            throw new IllegalStateException(message);
        }

        // Find the first level exceeding the desired resolution
        double texelSize;
        Level targetLevel = this.levels.getLastLevel();
        for (int i = 0; i < this.getLevels().getLastLevel().getLevelNumber(); i++)
        {
            if (this.levels.isLevelEmpty(i))
                continue;

            texelSize = this.levels.getLevel(i).getTexelSize();
            if (texelSize > resolution)
                continue;

            targetLevel = this.levels.getLevel(i);
            break;
        }

        // Choose the level closest to the resolution desired
        if (targetLevel.getLevelNumber() != 0 && !this.levels.isLevelEmpty(targetLevel.getLevelNumber() - 1))
        {
            Level nextLowerLevel = this.levels.getLevel(targetLevel.getLevelNumber() - 1);
            double dless = Math.abs(nextLowerLevel.getTexelSize() - resolution);
            double dmore = Math.abs(targetLevel.getTexelSize() - resolution);
            if (dless < dmore)
                targetLevel = nextLowerLevel;
        }

        Logging.verbose(Logging.getMessage("layers.TiledImageLayer.LevelSelection",
            targetLevel.getLevelNumber(), Double.toString(targetLevel.getTexelSize())));
        return targetLevel.getLevelNumber();
    }

    public long countImagesInSector(Sector sector, int levelNumber)
    {
        if (sector == null)
        {
            String msg = Logging.getMessage("nullValue.SectorIsNull");
            Logging.error(msg);
            throw new IllegalArgumentException(msg);
        }

        Level targetLevel = this.levels.getLastLevel();
        if (levelNumber >= 0)
        {
            for (int i = levelNumber; i < this.getLevels().getLastLevel().getLevelNumber(); i++)
            {
                if (this.levels.isLevelEmpty(i))
                    continue;

                targetLevel = this.levels.getLevel(i);
                break;
            }
        }

        // Collect all the tiles intersecting the input sector.
        LatLon delta = targetLevel.getTileDelta();
        LatLon origin = this.levels.getTileOrigin();
        int nwRow = Tile.computeRow(delta.latitude, sector.maxLatitude, origin.latitude);
        int nwCol = Tile.computeColumn(delta.longitude, sector.minLongitude, origin.longitude);
        int seRow = Tile.computeRow(delta.latitude, sector.minLatitude, origin.latitude);
        int seCol = Tile.computeColumn(delta.longitude, sector.maxLongitude, origin.longitude);

        long numRows = nwRow - seRow + 1;
        long numCols = seCol - nwCol + 1;

        return numRows * numCols;
    }

    public GpuTextureTile[][] getTilesInSector(Sector sector, int levelNumber)
    {
        if (sector == null)
        {
            String msg = Logging.getMessage("nullValue.SectorIsNull");
            Logging.error(msg);
            throw new IllegalArgumentException(msg);
        }

        Level targetLevel = this.levels.getLastLevel();
        if (levelNumber >= 0)
        {
            for (int i = levelNumber; i < this.getLevels().getLastLevel().getLevelNumber(); i++)
            {
                if (this.levels.isLevelEmpty(i))
                    continue;

                targetLevel = this.levels.getLevel(i);
                break;
            }
        }

        // Collect all the tiles intersecting the input sector.
        LatLon delta = targetLevel.getTileDelta();
        LatLon origin = this.levels.getTileOrigin();
        int nwRow = Tile.computeRow(delta.latitude, sector.maxLatitude, origin.latitude);
        int nwCol = Tile.computeColumn(delta.longitude, sector.minLongitude, origin.longitude);
        int seRow = Tile.computeRow(delta.latitude, sector.minLatitude, origin.latitude);
        int seCol = Tile.computeColumn(delta.longitude, sector.maxLongitude, origin.longitude);

        int numRows = nwRow - seRow + 1;
        int numCols = seCol - nwCol + 1;
        GpuTextureTile[][] sectorTiles = new GpuTextureTile[numRows][numCols];

        for (int row = nwRow; row >= seRow; row--)
        {
            for (int col = nwCol; col <= seCol; col++)
            {
                TileKey key = new TileKey(targetLevel.getLevelNumber(), row, col, targetLevel.getCacheName());
                Sector tileSector = this.levels.computeSectorForKey(key);
                sectorTiles[nwRow - row][col - nwCol] = this.createTile(tileSector, targetLevel, row, col);
            }
        }

        return sectorTiles;
    }
}